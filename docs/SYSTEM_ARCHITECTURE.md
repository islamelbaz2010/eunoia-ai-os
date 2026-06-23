# System Architecture

Status: Draft v1

## 1. Architectural Style

Modular monolith on Next.js for product surface (UI + BFF API routes) with a **separate long-running worker tier on the VPS** for anything that exceeds Vercel's serverless execution limits: AI orchestration jobs, RAG ingestion, WhatsApp/Meta webhook processing, billing reconciliation, and scheduled credit sweeps.

This is not a microservices architecture in v1 — splitting further before there is real multi-team or multi-scale pressure would add operational cost the roadmap doesn't justify yet (Phase 1–3 is a small team shipping fast). The boundary that does exist (Next.js vs. worker) is drawn specifically because Vercel functions cannot run long-lived or queue-consuming processes.

## 2. High-Level Components

```
┌─────────────────────────────────────────────────────────────────┐
│  Client (Web App — Next.js, multi-tenant dashboard)             │
└───────────────────────────────┬───────────────────────────────────┘
                                 │ HTTPS (JWT / API key)
┌───────────────────────────────▼───────────────────────────────────┐
│  Next.js on Vercel                                               │
│  - UI (App Router, server components)                            │
│  - BFF API routes (REST, see API_ARCHITECTURE.md)                │
│  - Auth middleware (tenant resolution, see DATABASE_ARCHITECTURE) │
│  - Webhook receivers (signature verify → enqueue, return fast)   │
└─────────┬───────────────────────────────────────┬─────────────────┘
          │                                       │
          ▼                                       ▼
┌──────────────────────┐               ┌─────────────────────────────┐
│ Supabase             │               │ Job Queue (Postgres-backed, │
│ - Postgres + RLS      │◄─────────────┤  e.g. pgmq / Supabase cron) │
│ - Auth               │               └──────────────┬──────────────┘
│ - Storage            │                              │
│ - pgvector           │                              ▼
└──────────┬───────────┘               ┌─────────────────────────────┐
           │                           │  Worker Tier (VPS)          │
           │                           │  - AI Orchestration Service │
           │                           │  - RAG Ingestion Pipeline   │
           │                           │  - Integration Workers      │
           │                           │    (WhatsApp, Meta)         │
           │                           │  - Billing Reconciliation   │
           │                           │  - Credit Expiry Sweeper    │
           │                           └──────────────┬──────────────┘
           │                                          │
           ▼                                          ▼
┌──────────────────────┐               ┌─────────────────────────────┐
│ Stripe / Paymob       │               │ OpenAI / Anthropic / Gemini │
└──────────────────────┘               └─────────────────────────────┘
```

## 3. Component Responsibilities

### Next.js on Vercel (request/response tier)
- Renders the tenant dashboard, handles synchronous CRUD via API routes.
- Resolves tenant context and enforces auth before any data access.
- Webhook endpoints (Stripe, Paymob, WhatsApp, Meta) **only verify signature and enqueue** — they never do business logic inline, to stay under Vercel's execution timeout and to avoid duplicate-processing on provider retries.
- Calls the AI Orchestration Service for synchronous, low-latency AI chat (request-response within Vercel's timeout); hands off anything long-running (bulk content generation, RAG ingestion, campaign generation) to the job queue.

### Job Queue
- Postgres-backed queue (`pgmq` or a `ai_jobs`/`webhook_events` table polled by workers) — avoids introducing a separate message broker (Redis/SQS) until volume requires it.
- Guarantees at-least-once delivery; all job handlers are idempotent (keyed by external event ID for webhooks, job ID for AI jobs).

### Worker Tier (VPS)
This is the home for everything Vercel can't run:
- **AI Orchestration Service**: provider-agnostic interface over OpenAI/Anthropic/Gemini (model routing, retries, fallback on provider outage, streaming back to client via Supabase Realtime or SSE proxy).
- **RAG Ingestion Pipeline**: chunking, embedding generation, pgvector writes — runs async because documents can be large and embedding calls are rate-limited.
- **Integration Workers**: WhatsApp Business API and Meta webhook consumers; these need persistent connections/polling patterns unsuited to serverless.
- **Billing Reconciliation**: nightly job reconciling Stripe/Paymob state against `subscriptions`/`invoices`.
- **Credit Expiry Sweeper**: scheduled job applying credit rollover/expiry rules from CREDITS_SYSTEM.md.

### Supabase
- System of record for all tenant data, auth, and file storage. See DATABASE_ARCHITECTURE.md.

## 4. AI Orchestration Design

- Single internal interface: `AIProvider.generate(messages, options) -> {content, tokensIn, tokensOut, model}` implemented per provider (OpenAI, Anthropic, Gemini).
- Model/provider selection is **policy-driven**, not hardcoded: a per-tenant or per-feature config decides default provider, with automatic fallback to a secondary provider on error/timeout/rate-limit.
- Every AI call is metered at the orchestration layer and written to `ai_messages` (tokens, cost) before the credit ledger entry is posted — orchestration never trusts the client to report usage.
- Streaming responses proxy through the Next.js edge for chat UX, while batch/async generation (campaign drafts, reports) is queued and delivered via Realtime/webhook-to-client-poll.

## 5. Security Boundaries

- Vercel tier never holds long-lived secrets for third-party AI providers beyond what's needed for the request; orchestration secrets live on the worker tier and are not exposed to the browser under any path.
- Worker tier reaches Supabase via job-specific least-privilege Postgres roles, not the service-role key, per the resolved decision in DATABASE_ARCHITECTURE.md §2.

### Resolved decision — Internal Vercel ↔ VPS authentication

**Final decision: short-lived signed JWTs issued by a minimal internal token-issuing service, layered over mTLS at the transport level.**

- A lightweight internal auth component (runs on the VPS, not Vercel) issues JWTs with a 60-second TTL, signed with an asymmetric key pair (private key on the issuer, public key distributed to verifiers). Claims include `job_type`, `org_id` (where applicable), and `iat`/`exp`.
- Every request from Vercel to the VPS worker tier (e.g. triggering a synchronous AI orchestration call) carries this token; the VPS ingress verifies signature and expiry before any handler runs. Tokens are never reused past expiry — no refresh, just reissue.
- Transport is additionally secured with mutual TLS between Vercel's egress and the VPS ingress, so a stolen/leaked JWT alone is insufficient without also presenting a valid client certificate.
- Alternatives considered: (a) static shared secret header — rejected, no per-request expiry or scoping, a single leak compromises the channel indefinitely with no graceful rotation; (b) full OAuth2 client-credentials flow via a third-party identity provider — rejected as unnecessary latency and operational overhead for a single internal trust boundary; (c) mTLS alone with no token — rejected, provides transport trust but no claim-level scoping (job type, org context) for authorization decisions on the VPS side.
- Security impact: bounds the lifetime of any leaked credential to 60 seconds, and requires two independently-compromised secrets (private signing key + TLS client cert) for full impersonation. Scalability impact: negligible — JWT verification is local, no added network hop. Cost impact: near-zero; reuses existing certificate infrastructure, no new paid service.

## 6. Scalability Considerations

- Vercel tier scales automatically with request volume; no action needed.
- Worker tier scales horizontally by adding queue consumers; concrete numeric thresholds are defined in INFRASTRUCTURE.md §8 (resolved decision) rather than the qualitative "queue depth" signal alone.
- pgvector/RAG is the most likely first bottleneck as tenants grow knowledge bases — isolated as an explicit open item in DATABASE_ARCHITECTURE.md.

## 7. Failure Modes & Resilience

- AI provider outage: orchestration falls back to secondary provider per policy; if all providers fail, job is retried with exponential backoff, user sees a queued/retrying state, never a silent failure.
- Webhook processing failure: event persisted in `webhook_events` before ack; failed processing is retried from the queue, not by asking the provider to resend.
- Worker tier outage: queue continues to accept new jobs (durable in Postgres); backlog drains once workers recover — no data loss, only latency increase.

## 8. Non-Goals (v1)

- No microservices split beyond the Vercel/Worker boundary.
- No multi-region active-active deployment (single primary region, matching Supabase project region nearest to target markets — MENA/EU).
- No Kubernetes — the VPS runs the worker tier as managed processes (see INFRASTRUCTURE.md) until scale justifies orchestration overhead.
