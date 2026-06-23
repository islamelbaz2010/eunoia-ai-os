# Database Architecture

Status: Draft v1

## 1. Platform

- Postgres via Supabase (primary OLTP store)
- pgvector extension for RAG embeddings (co-located with tenant data, no separate vector DB for v1)
- Supabase Auth for identity, Supabase Storage for file/media assets

## 2. Multi-Tenancy Model

**Decision: Shared database, shared schema, Row-Level Security (RLS) per tenant.**

Rationale: lowest operational overhead at current scale, native to Supabase, avoids per-tenant migration fan-out. Revisit only if a single enterprise tenant requires physical data isolation (contractual/compliance) — those tenants can be moved to a dedicated Postgres instance later without changing the application data model.

- Every tenant-owned table carries a non-nullable `org_id uuid` column referencing `organizations.id`.
- RLS is enabled on every tenant-owned table. No table is queried without a policy.
- Application code never trusts a client-supplied `org_id`; it is always resolved server-side from the authenticated session/JWT claim.
- A Postgres role-level claim (`request.jwt.claims.org_id`) drives all RLS policies via `current_setting()`.

```sql
alter table public.contacts enable row level security;

create policy tenant_isolation on public.contacts
  using (org_id = (current_setting('request.jwt.claims', true)::json->>'org_id')::uuid)
  with check (org_id = (current_setting('request.jwt.claims', true)::json->>'org_id')::uuid);
```

- **Resolved decision — worker-tier RLS bypass risk**: workers never use the Supabase service-role key for per-job, tenant-scoped operations. Instead, dedicated Postgres roles are created per worker type (`ai_worker`, `rag_worker`, `integration_worker`, `billing_worker`) with `BYPASSRLS` **revoked**. Each role authenticates its session and sets `app.current_org_id` via `SET LOCAL` from the verified job payload before any query — the same RLS policies that protect the API tier also protect these roles, so a bug in worker code cannot cross tenant boundaries even if the job payload is malformed (a missing/invalid `org_id` simply yields zero rows, not another tenant's rows).
  - The Supabase service-role key (true RLS bypass) is reserved for exactly two genuinely cross-tenant code paths: the nightly billing reconciliation job and the credit-expiry sweeper, both of which legitimately need to scan across all orgs. These two paths are isolated into their own audited module, run only on the `billing_worker` role, and every query they execute is logged to `audit_log` with `actor_type = system_job`.
  - Alternatives considered: (a) giving every worker the service-role key — rejected, removes the database as a second line of defense entirely; (b) per-tenant database credentials — rejected, operationally explosive at hundreds of tenants with no automation benefit over RLS. Recommended architecture above keeps RLS as the actual enforcement boundary for all but two named, reviewed code paths.
  - Security impact: cross-tenant blast radius from a worker-tier bug is eliminated for AI orchestration, RAG, and integrations — the largest unmitigated risk from the self-review. Cost impact: negligible (role creation is one-time DDL); minor latency from `SET LOCAL` per job, not measurable at current scale.

## 3. Core Schema (v1)

### Identity & Tenancy
- `organizations` (id, name, industry_vertical, locale_default, status, created_at)
- `users` (id, auth_user_id [fk to Supabase auth.users], email, created_at)
- `organization_members` (org_id, user_id, role[owner|admin|member|billing], invited_by, joined_at)
- `api_keys` (org_id, key_hash, scopes[], created_by, last_used_at, revoked_at)

### CRM
- `contacts` (org_id, name, email, phone, locale, source, lifecycle_stage, custom_fields jsonb)
- `deals` (org_id, contact_id, stage, value, currency, owner_id)
- `activities` (org_id, contact_id, type[call|email|whatsapp|note], payload jsonb, created_at)

### RAG Knowledge Base
- `kb_documents` (org_id, source_type[upload|url|integration], title, status, created_at)
- `kb_chunks` (org_id, document_id, content, embedding vector(1536), metadata jsonb)
  - HNSW index per-tenant-filtered: `create index on kb_chunks using hnsw (embedding vector_cosine_ops);` with `org_id` as a leading filter predicate enforced by RLS, not the index itself.

### AI Orchestration
- `ai_conversations` (org_id, user_id, channel[chat|whatsapp|email], status)
- `ai_messages` (org_id, conversation_id, role, content, provider[openai|anthropic|gemini], model, tokens_in, tokens_out, cost_credits, created_at)
- `ai_jobs` (org_id, job_type, status[queued|running|succeeded|failed], payload jsonb, result jsonb, attempts)

### Credits & Billing (referenced here, owned by CREDITS_SYSTEM.md / BILLING_ARCHITECTURE.md)
- `credit_ledger` (org_id, delta, balance_after, reason, reference_type, reference_id, created_at) — append-only, never updated/deleted
- `subscriptions` (org_id, plan_id, status, provider[stripe|paymob], provider_subscription_id, current_period_end)
- `invoices` (org_id, provider, provider_invoice_id, amount, currency, status, issued_at)

### Automation & Integrations
- `integrations` (org_id, provider[whatsapp|meta|crm_external], credentials_encrypted, status)
- `automations` (org_id, trigger, conditions jsonb, actions jsonb, enabled)
- `webhook_events` (org_id nullable, provider, event_type, payload jsonb, status[pending|resolved|unresolved|processed], resolution_attempts, processed_at, created_at) — `org_id` nullable because inbound webhooks are resolved to a tenant after signature verification, not before.

#### Resolved decision — webhook org_id resolution failure handling

**Final decision: unresolved events are never dropped silently — they move through an explicit, bounded retry-then-dead-letter flow.**

1. On receipt (signature already verified), the event is inserted with `status = pending` and `org_id = null` if the tenant can't yet be resolved (e.g. a WhatsApp/Meta account ID not yet linked to an org, or arriving mid-onboarding).
2. A resolution worker retries `org_id` lookup on a backoff schedule (e.g. every 5 min) for up to 24 hours — covering the realistic case of a webhook arriving slightly ahead of the integration record that links it to a tenant.
3. If resolved within the window, `org_id` is set, `status = resolved`, and normal processing proceeds.
4. If still unresolved after 24 hours, `status = unresolved` and the event is treated as dead-lettered: it stops auto-retrying, and a Sentry alert + ops notification fires for manual investigation. It remains queryable (never deleted) so support/ops can manually attach it to the correct org if discovered later.
- Alternatives considered: (a) drop unresolvable events after signature verification — rejected, this is exactly the silent-failure gap identified in self-review and is unacceptable for billing-adjacent webhooks (Stripe/Paymob); (b) block/retry indefinitely with no dead-letter — rejected, would let a permanently broken integration mapping accumulate retries forever with no human visibility.
- Security impact: removes a silent-failure path that could otherwise mask a missed billing or integration event indefinitely. Scalability impact: negligible — resolution attempts are bounded and infrequent. Cost impact: none beyond the alerting already in place for other ledger/billing failures.

### Audit
- `audit_log` (org_id, actor_id, action, resource_type, resource_id, metadata jsonb, created_at) — append-only, retained per compliance requirements per vertical (medical clinics require longer retention).

## 4. Tenant Resolution Flow

1. Request arrives with a Supabase JWT (web) or API key (server-to-server).
2. Edge middleware resolves `org_id` from JWT claims or from `api_keys` lookup (hashed comparison only).
3. `org_id` is injected into the Postgres session via `set_config('request.jwt.claims', ...)` for the duration of the request/transaction.
4. All queries rely on RLS — no `WHERE org_id = ?` is trusted as the sole isolation mechanism, though application code still includes it defensively (belt-and-braces, never belt-only).

## 5. Encryption & Sensitive Data

- Integration credentials (`integrations.credentials_encrypted`) encrypted at the application layer (AES-256-GCM) before storage — never stored as plaintext, never relies on disk-level encryption alone.
- PII columns (contacts, patient data for medical-clinic tenants) flagged in a `data_classification` registry table to drive retention and export/delete-on-request tooling (GDPR Art. 17 support).

### Resolved decision — KMS vs. Supabase Vault

**Final decision: Supabase Vault is the default key-management layer for v1, used with envelope encryption so the underlying key custodian can be swapped without re-encrypting data.**

- Data Encryption Keys (DEKs) generated per-tenant, used to encrypt `integrations.credentials_encrypted` and other sensitive columns at the application layer.
- DEKs are themselves wrapped (encrypted) by a master Key Encryption Key (KEK) stored in Supabase Vault — the application never stores or transmits an unwrapped KEK.
- Alternatives considered: (a) external KMS (AWS KMS/GCP KMS) from day one — rejected for v1, adds cross-cloud latency and operational surface with no compliance requirement yet justifying it; (b) Supabase Vault with no envelope pattern (encrypt directly with the Vault-managed key) — rejected, makes a future KMS migration require re-encrypting every row instead of just re-wrapping keys.
- Recommended architecture: envelope encryption now, with the KEK swap to an external KMS (AWS KMS or GCP KMS) reserved as a defined migration path the moment a tenant's compliance requirement (e.g. a medical-clinic tenant needing key custody outside the database provider) demands it. The migration only re-wraps DEKs, not tenant data.
- Security impact: contains blast radius of a Vault compromise to wrapped keys, not plaintext credentials; matches data-classification tiers (medical PII can be required to use external KMS once that compliance need is real). Scalability impact: none meaningful at current volume. Cost impact: $0 incremental now; external KMS adds a small per-key/per-call cost only if/when migrated.

## 6. Migrations & Schema Change Policy

- All schema changes via versioned SQL migrations (Supabase CLI), reviewed in PR, never applied via the dashboard in production.
- Backwards-compatible migrations only (additive columns, nullable-first) to support zero-downtime deploys on Vercel.
- No tenant-specific schema drift — every tenant runs on the exact same schema version at all times.

## 7. Backups & Disaster Recovery

- Supabase point-in-time recovery (PITR) enabled, minimum 7-day window (raise per-plan for enterprise tenants).
- Logical daily export of `credit_ledger`, `invoices`, `audit_log` to cold storage (append-only tables are the financial/compliance source of truth and must survive a full project loss).
- Recovery objective: RPO ≤ 5 minutes (PITR), RTO ≤ 1 hour for full project restore.

## 8. Open Items for Future Revisions

- Decide vector store migration path if `kb_chunks` volume per tenant outgrows pgvector performance (candidate: dedicated vector DB, isolated per-tenant namespace).
- Decide whether high-tier/enterprise tenants get a dedicated Postgres instance (schema stays identical; only physical placement changes).
