# Phase 1 Task Breakdown

## Workstream 1: Project Scaffold

### P1-001 Create Next.js application

- Create app with TypeScript, App Router, Tailwind, ESLint.
- Add `src/` directory.
- Add route groups for auth, app, and admin.
- Add base layout and dashboard shell.

Acceptance:

- `npm run dev` starts locally.
- Home route redirects based on auth state.

### P1-002 Add environment validation

- Add typed environment schema.
- Fail fast when required variables are missing.
- Separate browser-safe and server-only variables.

Acceptance:

- Invalid env blocks app boot in development and CI.

### P1-003 Add Supabase clients

- Browser client.
- Server component client.
- Route handler client.
- Admin service client restricted to server-only modules.

Acceptance:

- No service key can be imported by client code.

## Workstream 2: Database and Supabase

### P1-010 Apply Phase 1 migrations

- Extensions.
- Enums.
- Tenant tables.
- CRM tables.
- Knowledge base tables.
- AI chat tables.
- Usage/audit tables.
- RLS policies.
- Storage buckets.

Acceptance:

- All migrations run on an empty Supabase project.

### P1-011 Generate database types

- Generate TypeScript types from Supabase.
- Commit generated types after schema stabilizes.

Acceptance:

- API handlers use generated types.

### P1-012 Seed local development data

- Create sample organization.
- Create sample users.
- Create CRM sample data.
- Create sample knowledge records.

Acceptance:

- Developer can run one seed command after migration.

## Workstream 3: Auth and RBAC

### P1-020 Implement auth pages

- Login.
- Signup invite acceptance.
- Logout.
- Auth callback.

Acceptance:

- User can authenticate through Supabase.

### P1-021 Implement protected route middleware

- Redirect unauthenticated users.
- Load current organization.
- Block access without membership.

Acceptance:

- Protected pages cannot be accessed anonymously.

### P1-022 Implement RBAC helpers

- `requireRole`
- `canRead`
- `canWrite`
- `canManageOrg`
- `canAccessSuperAdmin`

Acceptance:

- All route handlers call centralized RBAC helpers.

### P1-023 Implement super admin access

- Global `super_admins` table.
- Super admin layout.
- Super admin guards.

Acceptance:

- Super admin can access admin routes.
- Organization users cannot.

## Workstream 4: Multi-Tenant Organizations

### P1-030 Organization model

- Organization list.
- Current org switcher.
- Organization settings page.
- Trial/status fields.

Acceptance:

- User can switch between organizations they belong to.

### P1-031 Member management

- Member list.
- Role display.
- Invite placeholder flow for Phase 1 manual onboarding.

Acceptance:

- Owner can view members and roles.

## Workstream 5: CRM

### P1-040 Contacts

- List contacts.
- Create contact.
- Edit contact.
- View contact detail.

Acceptance:

- Contact CRUD is tenant scoped.

### P1-041 Leads

- Lead list.
- Lead pipeline status.
- Create and update leads.
- Convert lead to contact.

Acceptance:

- Lead lifecycle is visible on dashboard.

### P1-042 Activities and notes

- Add activity.
- Add note.
- View timeline per contact/lead.

Acceptance:

- Activities and notes are append-only from UI.

## Workstream 6: Knowledge Base

### P1-050 Document upload

- Upload to Supabase Storage.
- Insert document metadata.
- Mark status `pending`.

Acceptance:

- Uploaded file appears in organization knowledge base.

### P1-051 Document processing

- Extract text.
- Chunk text.
- Generate embeddings.
- Store chunks.
- Mark status `ready` or `failed`.

Acceptance:

- Processing can be rerun safely for failed documents.

### P1-052 Knowledge search

- Query embedding.
- Vector search scoped by `org_id`.
- Return top chunks.

Acceptance:

- Search never returns another organization's chunks.

## Workstream 7: AI Assistant

### P1-060 Chat API

- Create conversation.
- Store user message.
- Retrieve context.
- Generate answer.
- Store assistant message.
- Write usage event.

Acceptance:

- Chat response includes persisted conversation history.

### P1-061 Chat UI

- Conversation list.
- Message composer.
- Streaming response or loading state.
- Source/context metadata panel.

Acceptance:

- User can chat with organization knowledge.

## Workstream 8: Dashboard

### P1-070 Leads dashboard

- New leads.
- Open leads.
- Booked/closed leads.
- Recent activity.

Acceptance:

- Dashboard data is tenant scoped.

### P1-071 Usage dashboard

- AI messages count.
- Knowledge searches.
- Uploaded documents.

Acceptance:

- Usage summary updates from `usage_events`.

## Workstream 9: Super Admin

### P1-080 Organizations panel

- List organizations.
- Filter by status.
- View organization detail.
- Change trial/status.

Acceptance:

- Status changes write audit entries.

### P1-081 Users panel

- List users.
- View memberships.

Acceptance:

- Super admin can diagnose account membership issues.

## Workstream 10: Security and Quality

### P1-090 RLS tests

- Test cross-tenant read denial.
- Test viewer write denial.
- Test super admin route guard.

Acceptance:

- Tests fail if policies are removed.

### P1-091 CI setup

- Lint.
- Typecheck.
- Unit tests.
- Migration dry-run.

Acceptance:

- PR cannot merge if checks fail.

## Critical Path

1. Migrations
2. Supabase clients
3. Auth
4. RBAC
5. Organizations
6. CRM
7. Knowledge upload/search
8. AI chat
9. Dashboard
10. Super admin

