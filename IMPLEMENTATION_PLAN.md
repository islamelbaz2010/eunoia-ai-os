# Phase 1 Implementation Plan

## Objective

Build Phase 1 of Eunoia AI OS on `main`: multi-tenant organizations, authentication, RBAC, CRM, knowledge base, RAG assistant, dashboards, and super admin operations.

This plan treats the existing repository documentation as source of truth and converts it into an execution path. It does not include Marketplace, Voice AI, White Label, Enterprise features, agency pooling, advanced billing, advanced credits, or mobile apps.

## Repository Audit

Current `main` contains documentation only:

- `README.md`
- `docs/PRD.md`
- `docs/ROADMAP.md`
- `docs/PROJECT_DECISIONS.md`
- `docs/SYSTEM_ARCHITECTURE.md`
- `docs/DATABASE_ARCHITECTURE.md`
- `docs/API_ARCHITECTURE.md`
- `docs/INFRASTRUCTURE.md`
- `docs/BILLING_ARCHITECTURE.md`
- `docs/CREDITS_SYSTEM.md`

Missing implementation files:

- No Next.js application scaffold.
- No package manifest.
- No Supabase project configuration.
- No database migrations.
- No generated client types.
- No API route handlers.
- No UI components.
- No auth middleware.
- No seed scripts.
- No CI configuration.
- No environment validation.

Build specifications from repository branch history were also reviewed as implementation context:

- `docs/DATABASE_SCHEMA_SPEC.md`
- `docs/API_CONTRACT_SPEC.md`
- `docs/UNIT_ECONOMICS.md`
- `docs/ARCHITECTURE_READINESS_REPORT.md`

## Phase 1 Product Surface

Phase 1 ships a secure SaaS foundation:

1. Multi-tenant organizations
2. Supabase authentication
3. RBAC
4. CRM contacts, leads, activities, notes
5. Knowledge base document upload, storage, chunking, embeddings, search
6. AI assistant chat with context retrieval
7. Organization dashboard for leads, activities, usage
8. Super admin panel for organizations, users, trials, status

## Major Architecture Decisions

### Next.js App Router

Use Next.js App Router for product UI and API routes. This aligns with the existing system architecture: one modular monolith on Vercel for UI and BFF routes.

### Supabase First

Use Supabase for:

- Auth
- Postgres
- Row Level Security
- Storage
- pgvector

This minimizes infrastructure and manual setup while matching documented architecture.

### Server-Side Tenant Resolution

Every request resolves tenant context server-side. Client-provided `org_id` is never trusted. All tenant tables include `org_id`, and RLS enforces isolation.

### Phase 1 RBAC Roles

Use the roles required by this execution brief:

- `super_admin`
- `organization_owner`
- `executive`
- `analyst`
- `viewer`

Super admin is global and not tied to one tenant. Organization roles are scoped through `organization_members`.

### RAG V1

Use Supabase Storage for document assets, Postgres for metadata/chunks, and pgvector for embeddings. Defer dedicated vector DB until real volume demands it.

### Minimal Usage Tracking

Phase 1 tracks usage events for AI and knowledge search. It does not implement advanced credits or automated billing.

## Implementation Phases

### Phase 1A: Foundation

Deliver:

- Next.js app scaffold
- Supabase client/server helpers
- environment validation
- auth callback routes
- middleware
- database migrations
- seed script
- CI checks

Exit criteria:

- Local app starts.
- Supabase migrations apply.
- Auth session works.
- Protected pages redirect correctly.

### Phase 1B: Multi-Tenant Core

Deliver:

- organizations
- users profile table
- organization_members
- global super admins
- RBAC helpers
- tenant switcher
- organization settings

Exit criteria:

- User can belong to one or more organizations.
- Role checks work server-side.
- RLS prevents cross-tenant reads.
- Super admin can view all organizations.

### Phase 1C: CRM

Deliver:

- contacts
- leads
- activities
- notes
- lead status pipeline
- dashboard metrics

Exit criteria:

- Users can create and update leads.
- Users can log activities and notes.
- Dashboard shows lead/activity counts.
- Viewer role is read-only.

### Phase 1D: Knowledge Base

Deliver:

- document upload
- document metadata
- chunk storage
- embedding generation job
- search endpoint
- document status

Exit criteria:

- Organization uploads a document.
- Chunks are stored with embeddings.
- Search returns org-scoped results only.

### Phase 1E: AI Assistant

Deliver:

- conversations
- messages
- RAG context retrieval
- AI provider adapter
- chat endpoint
- chat UI
- usage event tracking

Exit criteria:

- User asks a question.
- Relevant org knowledge is retrieved.
- AI answer cites retrieved context in metadata.
- Conversation history is stored per tenant.

### Phase 1F: Super Admin

Deliver:

- organization list
- user list
- trial/status controls
- usage view
- audit log view

Exit criteria:

- Super admin can inspect tenants without bypassing audit.
- Status/trial changes are recorded.

## Automation Plan

Automate:

- `supabase db push` compatible migrations
- seed data for local development
- environment validation
- generated Supabase TypeScript types
- lint/typecheck/test checks
- CI workflow preparation
- local setup script

Manual only:

- Production secret values
- Supabase project creation
- provider API key issuance

## Required Environment Variables

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_DB_URL
OPENAI_API_KEY
AI_DEFAULT_MODEL
APP_URL
INTERNAL_CRON_SECRET
```

## Validation Gates

Before first deploy:

- Migrations apply from empty database.
- RLS tests pass.
- Typecheck passes.
- Lint passes.
- API route tests pass for auth, RBAC, tenant isolation.
- Upload/search/chat smoke test passes.

Before first customer:

- Super admin seed exists.
- Trial/status operations work.
- Document upload and search work.
- AI chat works with org-scoped context.
- Audit log records sensitive admin actions.

## Completion Definition

Phase 1 is implementation-ready when the artifacts in this commit exist and development can start by following:

1. `SUPABASE_SETUP_GUIDE.md`
2. `DATABASE_MIGRATIONS/README.md`
3. `NEXTJS_APP_STRUCTURE.md`
4. `API_IMPLEMENTATION_PLAN.md`
5. `PHASE_1_TASK_BREAKDOWN.md`

