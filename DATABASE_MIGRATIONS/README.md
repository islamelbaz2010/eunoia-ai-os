# Database Migrations

This directory contains Phase 1 Supabase SQL migrations.

Recommended final app location after scaffold:

```text
supabase/migrations/
```

Current files are generated as implementation-ready planning artifacts and should be copied or moved into `supabase/migrations/` when the Next.js/Supabase project scaffold is created.

## Order

1. `0001_extensions_and_types.sql`
2. `0002_tenancy_auth_rbac.sql`
3. `0003_crm.sql`
4. `0004_knowledge_base.sql`
5. `0005_ai_assistant_usage.sql`
6. `0006_audit_storage_and_admin.sql`

## Apply Locally

```bash
supabase start
supabase db reset
```

## Phase 1 Scope

Included:

- organizations
- users profile table
- super admins
- organization members
- contacts
- leads
- activities
- notes
- knowledge documents
- knowledge chunks
- AI conversations
- AI messages
- usage events
- audit log
- RLS policies
- storage bucket policy notes

Not included:

- advanced billing
- advanced credits
- agency pooling
- marketplace
- voice AI
- white label

