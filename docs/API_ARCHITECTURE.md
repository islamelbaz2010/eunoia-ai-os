# API Architecture

Status: Draft v1

## 1. Principles

- API-first: every dashboard feature is implemented against the same API surface external integrators/developers would use — no UI-only backdoor logic.
- REST over HTTPS, JSON payloads, versioned from day one (`/api/v1/...`) so Phase 4 Marketplace and third-party developer access don't require a breaking migration.
- Multi-tenant by construction: every authenticated request resolves exactly one `org_id`; cross-tenant access is structurally impossible, not just policy-enforced (backed by DB RLS, see DATABASE_ARCHITECTURE.md).

## 2. Surface

```
/api/v1/
  /auth/*                  - session, API key management
  /orgs/{orgId}            - org profile, settings, locale
  /contacts                - CRM
  /deals
  /activities
  /knowledge-base/documents
  /knowledge-base/search   - RAG query endpoint
  /ai/chat                 - synchronous chat completion (streaming)
  /ai/jobs                 - async generation jobs (campaigns, reports)
  /ai/jobs/{jobId}
  /automations
  /integrations/whatsapp
  /integrations/meta
  /credits/balance
  /credits/ledger
  /billing/subscription
  /billing/invoices
  /webhooks/stripe
  /webhooks/paymob
  /webhooks/whatsapp
  /webhooks/meta
```

## 3. Authentication

Two supported credential types, both resolving to an `org_id` + permission scope before any handler runs:

1. **Session (web app)**: Supabase Auth JWT, short-lived, refreshed via Supabase client SDK. Used by the dashboard only.
2. **API Key (server-to-server / future marketplace integrators)**: `Authorization: Bearer eun_live_...`, stored hashed (never plaintext) in `api_keys`, scoped to specific permissions (e.g. `contacts:read`, `ai:chat`) and revocable per-key without rotating others.

No endpoint accepts a client-supplied `org_id` — it is always derived from the credential.

## 4. Authorization (RBAC)

Roles per `organization_members`: `owner`, `admin`, `member`, `billing`.

- `owner`/`admin`: full access including billing and integration credentials.
- `member`: CRM, AI chat, automations — no billing, no API key management.
- `billing`: billing/invoices/credits only, no CRM/AI access (for finance staff at agency/enterprise tenants).

Enforced at the API route layer (permission check) **and** at the database layer (RLS) — defense in depth, neither layer alone is trusted.

## 5. Request/Response Conventions

- All list endpoints support cursor-based pagination (`?cursor=...&limit=...`) — offset pagination is avoided to stay stable under concurrent writes.
- All mutating endpoints (`POST`/`PATCH`/`DELETE`) accept an `Idempotency-Key` header, required for AI job creation and billing-adjacent calls, to make client retries safe.
- Errors follow a consistent envelope:

```json
{
  "error": {
    "code": "insufficient_credits",
    "message": "Organization does not have enough credits to complete this request.",
    "request_id": "req_..."
  }
}
```

- Every response includes `request_id` for support/debugging traceability, correlated with `audit_log` and Sentry events.

## 6. Rate Limiting & Abuse Prevention

- Per-API-key and per-org rate limits, enforced at the Vercel edge middleware before any DB/AI call is made.
- AI endpoints (`/ai/chat`, `/ai/jobs`) have a stricter tenant-level concurrency cap independent of credit balance, to prevent runaway automation loops from a single misconfigured tenant from degrading the platform for others.
- Webhook endpoints validate provider signatures before any processing (Stripe signature, Meta `X-Hub-Signature-256`, WhatsApp verify token) — unsigned/invalid payloads are rejected with `401` and never enqueued.

## 7. AI Endpoints — Specifics

- `POST /ai/chat`: synchronous, streamed via SSE, bounded to Vercel's function timeout. Used for interactive chat only.
- `POST /ai/jobs`: async, returns `202` with a `job_id` immediately; long-running generation (campaign plans, multi-document reports) runs on the worker tier (see SYSTEM_ARCHITECTURE.md) and is polled or pushed via Supabase Realtime.
- Both endpoints debit credits atomically with the AI call (see CREDITS_SYSTEM.md) — a failed AI call never debits; a successful call always does, in the same transaction as the usage record.

## 8. Versioning & Deprecation

- Breaking changes only ship under a new version prefix (`/api/v2`); old versions are supported for a published deprecation window (minimum 6 months) once external/marketplace developers exist.
- Additive, backwards-compatible changes (new optional fields, new endpoints) ship without a version bump.

## 9. Future: Marketplace / Public Developer API

- The same internal API is the foundation for Phase 4 Marketplace access — no parallel "public API" will be built. Marketplace apps authenticate via scoped API keys and OAuth-style consent per organization, reusing the RBAC model above.
