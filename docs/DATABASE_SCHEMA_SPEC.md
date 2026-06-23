# Database Schema Specification

Status: Build-Ready v1
Derived from: DATABASE_ARCHITECTURE.md, CREDITS_SYSTEM.md, BILLING_ARCHITECTURE.md

This is the implementation-level companion to DATABASE_ARCHITECTURE.md — every table here is ready to be expressed as a Supabase migration. Conventions: all primary keys are `uuid default gen_random_uuid()`; all tables have `created_at timestamptz not null default now()` unless noted; all tenant-owned tables have RLS enabled with the standard tenant-isolation policy from DATABASE_ARCHITECTURE.md §2 unless noted otherwise.

## 1. Identity & Tenancy

### `organizations`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| name | text not null | |
| industry_vertical | text | enum-like: hotel, travel_agency, medical_clinic, real_estate |
| locale_default | text not null | ar, en, it, ru |
| status | text not null | pending_onboarding, trialing, active, past_due, canceled |
| created_at | timestamptz | |

- Indexes: `idx_organizations_status` on `(status)`.
- RLS: not tenant-scoped by `org_id` (this table *is* the tenant); RLS policy restricts row access to where `id` matches the caller's `org_id` claim.

### `users`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| auth_user_id | uuid not null unique | FK → `auth.users(id)` |
| email | text not null unique | |
| created_at | timestamptz | |

- Not tenant-owned (a user can belong to multiple orgs via `organization_members`); RLS restricts to `auth_user_id = auth.uid()`.

### `organization_members`
| Column | Type | Notes |
|---|---|---|
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| user_id | uuid not null | FK → `users(id)` on delete cascade |
| role | text not null | owner, admin, member, billing |
| invited_by | uuid | FK → `users(id)` |
| joined_at | timestamptz | |

- PK: `(org_id, user_id)`.
- Indexes: `idx_org_members_user` on `(user_id)` for "my orgs" lookups.
- RLS: standard tenant isolation on `org_id`; additionally readable by the member's own `user_id` row across orgs for org-switching UI.

### `api_keys`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| key_hash | text not null unique | SHA-256 of the key, never the raw key |
| scopes | text[] not null | e.g. `{contacts:read, ai:chat}` |
| created_by | uuid not null | FK → `users(id)` |
| last_used_at | timestamptz | |
| revoked_at | timestamptz | nullable |

- Indexes: `idx_api_keys_org` on `(org_id)`, unique on `key_hash`.
- RLS: standard tenant isolation; only `owner`/`admin` role can write (enforced at API layer per RBAC).

## 2. CRM

### `contacts`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| name | text not null | |
| email | text | |
| phone | text | |
| locale | text | |
| source | text | |
| lifecycle_stage | text | lead, qualified, customer, churned |
| custom_fields | jsonb default '{}' | |
| created_at | timestamptz | |

- Indexes: `idx_contacts_org` on `(org_id)`, `idx_contacts_org_email` on `(org_id, email)`, `idx_contacts_lifecycle` on `(org_id, lifecycle_stage)`.
- RLS: standard tenant isolation.

### `deals`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| contact_id | uuid not null | FK → `contacts(id)` on delete cascade |
| stage | text not null | |
| value | numeric(12,2) | |
| currency | text not null default 'USD' | |
| owner_id | uuid | FK → `users(id)` |
| created_at | timestamptz | |

- Indexes: `idx_deals_org` on `(org_id)`, `idx_deals_contact` on `(contact_id)`.
- RLS: standard tenant isolation.

### `activities`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| contact_id | uuid | FK → `contacts(id)` on delete cascade |
| type | text not null | call, email, whatsapp, note |
| payload | jsonb default '{}' | |
| created_at | timestamptz | |

- Indexes: `idx_activities_org_contact` on `(org_id, contact_id, created_at desc)`.
- RLS: standard tenant isolation.
- **Partitioning**: candidate for monthly range partitioning on `created_at` once activity volume per org grows materially (high-write, append-heavy table); not implemented in v1, schema is partition-ready (no natural-key constraints that block converting to a partitioned table later).

## 3. RAG Knowledge Base

### `kb_documents`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| source_type | text not null | upload, url, integration |
| title | text not null | |
| status | text not null | pending, ingesting, ready, failed |
| created_at | timestamptz | |

- Indexes: `idx_kb_documents_org` on `(org_id)`.
- RLS: standard tenant isolation.

### `kb_chunks`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| document_id | uuid not null | FK → `kb_documents(id)` on delete cascade |
| content | text not null | |
| embedding | vector(1536) | |
| metadata | jsonb default '{}' | |
| created_at | timestamptz | |

- Indexes: `idx_kb_chunks_org` on `(org_id)`; `idx_kb_chunks_hnsw` — `create index using hnsw (embedding vector_cosine_ops)`. Application-layer queries always include `org_id` in the `WHERE` clause in addition to RLS (defense in depth) because HNSW does not natively partition by tenant.
- RLS: standard tenant isolation.
- **Partitioning**: not implemented in v1. Open item (DATABASE_ARCHITECTURE.md §8): if a single tenant's chunk volume materially degrades shared HNSW index performance, evaluate list-partitioning by `org_id` or migrating large tenants to a dedicated vector namespace.

## 4. AI Orchestration

### `ai_conversations`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| user_id | uuid | FK → `users(id)` |
| channel | text not null | chat, whatsapp, email |
| status | text not null | active, closed | 
| created_at | timestamptz | |

- Indexes: `idx_ai_conversations_org` on `(org_id, created_at desc)`.
- RLS: standard tenant isolation.

### `ai_messages`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| conversation_id | uuid not null | FK → `ai_conversations(id)` on delete cascade |
| role | text not null | user, assistant, system |
| content | text not null | |
| provider | text not null | openai, anthropic, gemini |
| model | text not null | |
| tokens_in | integer not null default 0 | |
| tokens_out | integer not null default 0 | |
| cost_credits | numeric(10,4) not null default 0 | |
| created_at | timestamptz | |

- Indexes: `idx_ai_messages_org_conversation` on `(org_id, conversation_id, created_at)`.
- RLS: standard tenant isolation.
- **Partitioning**: candidate for monthly range partitioning on `created_at` — this is the highest-volume table in the schema (one row per AI turn) and the most likely first table to need it. Not implemented in v1; flagged for first re-evaluation once production volume data exists.

### `ai_jobs`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| job_type | text not null | campaign_generation, report, rag_ingestion, ... |
| status | text not null default 'queued' | queued, running, succeeded, failed |
| payload | jsonb not null | |
| result | jsonb | |
| attempts | integer not null default 0 | |
| created_at | timestamptz | |

- Indexes: `idx_ai_jobs_status_created` on `(status, created_at)` — primary queue-polling index; `idx_ai_jobs_org` on `(org_id)`.
- RLS: standard tenant isolation for read by tenant; insert/update restricted to worker roles (`ai_worker`) per DATABASE_ARCHITECTURE.md §2.

### `ai_pricing_table`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| provider | text not null | |
| model | text not null | |
| credits_per_1k_input_tokens | numeric(10,4) not null | |
| credits_per_1k_output_tokens | numeric(10,4) not null | |
| effective_from | timestamptz not null | |

- Indexes: `idx_ai_pricing_lookup` on `(provider, model, effective_from desc)`.
- RLS: not tenant-owned (global, platform-managed); read-only to all authenticated roles, write restricted to internal ops role.

## 5. Credits & Billing

### `credit_ledger`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` |
| delta | numeric(12,4) not null | positive or negative |
| balance_after | numeric(12,4) not null | |
| reason | text not null | subscription_grant, credit_purchase, ai_usage, reservation, refund, expiry, adjustment |
| reference_type | text | ai_message, subscription, invoice, manual |
| reference_id | uuid | |
| created_at | timestamptz | |

- Table is **append-only**: no `UPDATE`/`DELETE` grants to any application role; enforced via a `REVOKE UPDATE, DELETE` on the table for all roles except a break-glass migration role.
- Indexes: `idx_credit_ledger_org_created` on `(org_id, created_at desc)` — primary balance-read and history-read path; `idx_credit_ledger_reference` on `(reference_type, reference_id)`.
- RLS: standard tenant isolation for read; insert restricted to `ai_worker`/`billing_worker` roles and the API tier's authenticated request path (never direct client insert).
- **Partitioning**: candidate for monthly range partitioning on `created_at` once volume justifies it — same rationale as `ai_messages`; not implemented in v1.

### `plans`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| name | text not null | Starter, Growth, Enterprise |
| credit_allotment | numeric(12,4) not null | |
| rollover_cap | numeric(12,4) not null default 0 | |
| price | numeric(10,2) not null | |
| currency | text not null | |
| billing_interval | text not null | monthly, annual |

- RLS: not tenant-owned, globally readable, write restricted to internal ops role.

### `plan_features`
| Column | Type | Notes |
|---|---|---|
| plan_id | uuid not null | FK → `plans(id)` on delete cascade |
| feature_key | text not null | e.g. `rag_document_limit`, `whatsapp_enabled`, `api_access` |
| limit_value | jsonb | numeric, boolean, or structured limit |

- PK: `(plan_id, feature_key)`.
- RLS: not tenant-owned, globally readable, write restricted to internal ops role.

### `subscriptions`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null unique | FK → `organizations(id)` — one active subscription per org |
| plan_id | uuid not null | FK → `plans(id)` |
| status | text not null | trialing, active, past_due, canceled |
| provider | text not null | stripe, paymob |
| provider_subscription_id | text not null | |
| current_period_end | timestamptz not null | |

- Indexes: `idx_subscriptions_provider_id` on `(provider, provider_subscription_id)` unique — webhook reconciliation lookup key.
- RLS: standard tenant isolation for read; write restricted to `billing_worker` role.

### `invoices`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` |
| provider | text not null | stripe, paymob |
| provider_invoice_id | text | |
| invoice_type | text not null | subscription, setup_fee, agency_service, credit_purchase |
| amount | numeric(12,2) not null | |
| currency | text not null | |
| status | text not null | open, paid, failed, refunded |
| issued_at | timestamptz | |

- Indexes: `idx_invoices_org` on `(org_id, issued_at desc)`, `idx_invoices_provider_id` on `(provider, provider_invoice_id)`.
- RLS: standard tenant isolation for read; write restricted to `billing_worker` role.

### `org_relationships`
| Column | Type | Notes |
|---|---|---|
| parent_org_id | uuid not null | FK → `organizations(id)` |
| child_org_id | uuid not null | FK → `organizations(id)` |
| relationship_type | text not null | agency_managed |
| credit_pool_enabled | boolean not null default false | Phase 4 feature flag, schema reserved in Phase 3 |
| created_at | timestamptz | |

- PK: `(parent_org_id, child_org_id)`.
- RLS: readable by either `parent_org_id` or `child_org_id` matching the caller's org claim; write restricted to internal ops role.

## 6. Automation & Integrations

### `integrations`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| provider | text not null | whatsapp, meta, crm_external |
| credentials_encrypted | bytea not null | AES-256-GCM ciphertext, envelope-encrypted per DATABASE_ARCHITECTURE.md §5 |
| status | text not null | connected, disconnected, error |
| created_at | timestamptz | |

- Indexes: `idx_integrations_org_provider` on `(org_id, provider)` unique.
- RLS: standard tenant isolation; decryption only ever happens server-side (worker tier), never returned to the client.

### `automations`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid not null | FK → `organizations(id)` on delete cascade |
| trigger | text not null | |
| conditions | jsonb default '{}' | |
| actions | jsonb default '{}' | |
| enabled | boolean not null default true | |
| created_at | timestamptz | |

- Indexes: `idx_automations_org` on `(org_id)`.
- RLS: standard tenant isolation.

### `webhook_events`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid | nullable, FK → `organizations(id)` |
| provider | text not null | stripe, paymob, whatsapp, meta |
| provider_event_id | text not null | |
| event_type | text not null | |
| payload | jsonb not null | |
| status | text not null default 'pending' | pending, resolved, unresolved, processed |
| resolution_attempts | integer not null default 0 | |
| processed_at | timestamptz | |
| created_at | timestamptz | |

- Indexes: `idx_webhook_events_dedupe` on `(provider, provider_event_id)` unique — enforces webhook idempotency at the DB level; `idx_webhook_events_status` on `(status, created_at)` — resolution worker polling index.
- RLS: not tenant-owned for unresolved rows (org_id nullable); once `org_id` is set, standard tenant isolation applies for read; write restricted to `integration_worker`/`billing_worker` roles.

## 7. Audit

### `audit_log`
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | |
| org_id | uuid | nullable for system-level events |
| actor_id | uuid | FK → `users(id)`, nullable for `actor_type = system_job` |
| actor_type | text not null | user, system_job |
| action | text not null | |
| resource_type | text not null | |
| resource_id | uuid | |
| metadata | jsonb default '{}' | |
| created_at | timestamptz | |

- Indexes: `idx_audit_log_org_created` on `(org_id, created_at desc)`.
- RLS: standard tenant isolation for read (org-scoped rows); system-level rows (`org_id is null`) readable only by internal ops role.
- **Retention**: append-only, no delete grants; retention period configurable per vertical (medical-clinic tenants get extended retention) via the `data_classification` registry, not via per-row deletion.

## 8. RLS Strategy Summary

- Every tenant-owned table: `enable row level security` + the standard `tenant_isolation` policy from DATABASE_ARCHITECTURE.md §2, using `current_setting('request.jwt.claims', true)::json->>'org_id'`.
- Worker-tier roles (`ai_worker`, `rag_worker`, `integration_worker`, `billing_worker`) are subject to the same RLS policies via `SET LOCAL app.current_org_id` per job — `BYPASSRLS` is revoked from all of them.
- Exactly two code paths use the Supabase service-role key (true bypass): nightly billing reconciliation, credit-expiry sweeper — both audited via `audit_log` with `actor_type = system_job`.
- Global/platform tables (`plans`, `plan_features`, `ai_pricing_table`) are not tenant-scoped; read-only to authenticated roles, write restricted to an internal ops role.

## 9. Partitioning Strategy Summary

No table is partitioned in v1 — current expected volume does not require it and premature partitioning adds migration complexity without a measured need. Three tables are explicitly flagged as partition-ready candidates once production volume data justifies the change: `ai_messages`, `credit_ledger`, `activities` (all high-write, append-heavy, naturally range-partitionable on `created_at`). Re-evaluate after Phase 2 traffic data is available.
