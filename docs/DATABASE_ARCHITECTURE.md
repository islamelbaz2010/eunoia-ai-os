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

- Service-role/background jobs that must operate cross-tenant (billing reconciliation, credit expiry sweeps) use the Supabase service key and bypass RLS explicitly, scoped to narrow, audited code paths only.

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
- `webhook_events` (org_id nullable, provider, event_type, payload jsonb, processed_at) — `org_id` nullable because inbound webhooks are resolved to a tenant after signature verification, not before.

### Audit
- `audit_log` (org_id, actor_id, action, resource_type, resource_id, metadata jsonb, created_at) — append-only, retained per compliance requirements per vertical (medical clinics require longer retention).

## 4. Tenant Resolution Flow

1. Request arrives with a Supabase JWT (web) or API key (server-to-server).
2. Edge middleware resolves `org_id` from JWT claims or from `api_keys` lookup (hashed comparison only).
3. `org_id` is injected into the Postgres session via `set_config('request.jwt.claims', ...)` for the duration of the request/transaction.
4. All queries rely on RLS — no `WHERE org_id = ?` is trusted as the sole isolation mechanism, though application code still includes it defensively (belt-and-braces, never belt-only).

## 5. Encryption & Sensitive Data

- Integration credentials (`integrations.credentials_encrypted`) encrypted at the application layer (AES-256-GCM) before storage, key managed via Supabase Vault / KMS — never stored as plaintext, never relies on disk-level encryption alone.
- PII columns (contacts, patient data for medical-clinic tenants) flagged in a `data_classification` registry table to drive retention and export/delete-on-request tooling (GDPR Art. 17 support).

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
