# Infrastructure

Status: Draft v1

## 1. Environments

- `production`, `staging`, `preview` (per-PR Vercel preview deployments).
- Each environment has its own Supabase project — staging/preview never touch production data. Preview deployments use a shared staging Supabase project with seeded synthetic tenants, not production clones.

## 2. Hosting Topology

| Layer | Platform | Role |
|---|---|---|
| Web app + BFF API | Vercel | Next.js app, request/response tier, webhook signature verification |
| Database / Auth / Storage / Vector | Supabase | System of record, RLS-enforced multi-tenancy |
| Worker tier | VPS (managed by Eunoia) | AI orchestration, RAG ingestion, integration consumers, billing reconciliation, scheduled jobs |
| Error monitoring | Sentry | Frontend + API route + worker error tracking |
| Product analytics | PostHog | Usage analytics, feature adoption, funnel tracking |
| Email | Resend | Transactional email (invites, billing receipts, password resets) |

## 3. Why a VPS Alongside Vercel

Vercel serverless functions have execution time and connection-duration limits that don't fit:
- Long-running AI orchestration (multi-step agent flows, retries with backoff across providers)
- RAG ingestion (chunking + embedding generation over large documents)
- Persistent/polling consumers for WhatsApp Business API and Meta webhooks
- Scheduled financial jobs (credit expiry sweep, billing reconciliation) that must run reliably regardless of request traffic

The VPS runs these as supervised long-lived processes (e.g. via `systemd` or a process manager like PM2), each consuming from the Postgres-backed job queue described in SYSTEM_ARCHITECTURE.md.

## 4. Worker Tier Composition

- Each worker process type (AI orchestration, RAG ingestion, WhatsApp consumer, Meta consumer, billing reconciliation, credit sweeper) runs as an independently restartable service.
- Workers are stateless between jobs — all state lives in Postgres — so any worker can be killed and restarted without data loss, and horizontal scaling is just running more worker instances against the same queue.
- Initial deployment: single VPS, multiple worker processes. Scale path: split into multiple VPS instances by worker type once a specific queue (e.g. AI orchestration) becomes the bottleneck, without changing the queue contract.

## 5. Secrets Management

- Vercel: environment variables scoped per environment (production/staging/preview), never shared across environments.
- VPS: secrets loaded from a dedicated secrets manager (e.g. Doppler, or Supabase Vault accessed via service role) — never committed, never baked into images.
- AI provider keys, Stripe/Paymob keys, WhatsApp/Meta app secrets all rotate independently; rotation does not require a deploy of unrelated components.

## 6. Networking & Security

- VPS firewalled to accept inbound traffic only from: Vercel (signed internal token auth), Supabase, and provider IP ranges for webhook delivery where applicable.
- All inter-service traffic over TLS. No plaintext internal traffic, even within the same provider network.
- Database access restricted to Supabase connection pooling (PgBouncer) from known origins (Vercel, VPS) — no direct public Postgres exposure.

## 7. Observability

- Sentry: error tracking across Next.js (client + server) and worker tier processes, with `org_id` and `request_id` attached to every event for tenant-level triage.
- PostHog: product usage analytics, feature-flag-gated rollouts for new AI features per tenant/vertical.
- Structured logs (JSON) from worker tier shipped to a centralized log store; minimum retention 30 days, longer for audit-relevant job types.
- Key operational metrics: queue depth per job type, AI provider latency/error rate per provider, credit ledger write failures (alert immediately — financial data), webhook processing lag.

## 8. Scaling Triggers

### Resolved decision — queue scaling thresholds

**Final decision: numeric, per-job-type thresholds on queue depth and oldest-pending-job age, evaluated every 30 seconds, requiring both metrics to breach for 5 consecutive minutes before autoscaling (avoids flapping on transient spikes).**

| Job type | Queue depth threshold | Max oldest-job age | Action |
|---|---|---|---|
| AI orchestration (sync-adjacent) | > 50 pending | > 30s | Add worker instance immediately; user-facing latency, tightest threshold |
| RAG ingestion | > 200 pending | > 5 min | Add worker instance |
| Integration consumers (WhatsApp/Meta) | > 100 pending | > 2 min | Add worker instance |
| Billing reconciliation / credit sweep | N/A (scheduled, not queue-driven) | run overdue > 1 cycle | Alert on-call, does not autoscale |

- Alternatives considered: (a) CPU/memory-based autoscaling — rejected, doesn't reflect actual backlog (a worker can be CPU-idle while waiting on a slow AI provider call, masking a real backlog); (b) fixed worker count sized for peak — rejected, wastes cost at typical load and still has no defined ceiling for unexpected growth.
- Recommended architecture: the table above, implemented as a scheduled check (worker tier or a small monitoring script) that reads queue depth/age directly from the job tables and triggers a new worker process via the deployment pipeline (INFRASTRUCTURE.md §10).
- Security impact: none directly; reduces the chance that a backlog-induced slowdown leads to ad hoc, unaudited manual scaling changes under pressure. Scalability impact: gives the platform a concrete, testable autoscaling contract instead of an undefined "queue depth" signal. Cost impact: pay-for-what-you-need — workers scale down when thresholds are no longer breached (same review cadence, inverse direction), avoiding permanently over-provisioned VPS capacity.

### Other scaling signals

| Signal | Action |
|---|---|
| AI provider error rate spike | Orchestration fallback to secondary provider; alert on-call |
| Postgres connection saturation | Increase pooler limits / move heavy read paths to read replica |
| pgvector query latency degradation | Re-evaluate dedicated vector store (see DATABASE_ARCHITECTURE.md open items) |

## 9. Disaster Recovery

- Supabase PITR (RPO ≤ 5 min) per DATABASE_ARCHITECTURE.md.
- VPS worker tier is stateless and disposable — recovery is "provision new VPS, deploy same artifact, point at same queue," no data recovery needed on that tier.
- Documented runbook required before Phase 2 (integrations go live) — worker tier downtime during a WhatsApp/Meta outage must not drop messages, since inbound webhooks are durable in `webhook_events` regardless of worker availability.

## 10. CI/CD

- Vercel: automatic preview deploy per PR, automatic production deploy on merge to main, with required passing checks (typecheck, lint, tests).
- Worker tier: deploy via CI pipeline building a versioned artifact, deployed to VPS with zero-downtime restart (rolling restart across worker processes, queue ensures no job is lost mid-deploy).
- Database migrations run as a required, separate CI step before app deploy, never applied manually in production.
