# Supabase Setup Guide

## Goal

Create a Supabase project that can run Phase 1 locally, in staging, and in production with minimal manual work.

## Required Supabase Capabilities

- Auth
- Postgres
- Row Level Security
- Storage
- pgvector extension
- SQL migrations
- generated TypeScript types

## Environments

Create separate Supabase projects:

- `eunoia-local` through Supabase CLI
- `eunoia-staging`
- `eunoia-production`

Do not share production data with staging or preview environments.

## CLI Setup

Install Supabase CLI:

```bash
brew install supabase/tap/supabase
```

Login:

```bash
supabase login
```

Start local Supabase:

```bash
supabase start
```

Apply migrations:

```bash
supabase db reset
```

Generate types:

```bash
supabase gen types typescript --local > src/types/database.types.ts
```

## Storage Buckets

Phase 1 uses one private bucket:

```text
knowledge-documents
```

Rules:

- Private bucket.
- Object path must start with organization id.
- Max upload size should be configured by environment.
- Signed uploads only.

Suggested object path:

```text
{org_id}/{document_id}/{safe_filename}
```

## Auth Settings

Enable:

- Email/password or magic link for initial release.
- Email confirmation in production.
- Redirect URL: `APP_URL/auth/callback`

Disable until needed:

- Public self-serve OAuth providers.
- Anonymous auth.

## Super Admin Bootstrap

Create first super admin manually after the first auth user exists:

```sql
insert into public.super_admins (user_id, created_by)
select u.id, u.id
from public.users u
where u.email = 'founder@example.com'
on conflict (user_id) do nothing;
```

Replace the email before running.

## Local Seed Strategy

After migrations, seed:

- one organization
- one owner
- one executive
- one analyst
- one viewer
- sample contacts
- sample leads
- sample activities
- sample knowledge document metadata

Keep seed data synthetic.

## Environment Variables

```text
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
SUPABASE_DB_URL=
OPENAI_API_KEY=
AI_DEFAULT_MODEL=gpt-4.1-mini
APP_URL=http://localhost:3000
INTERNAL_CRON_SECRET=
```

## Production Setup Checklist

- Create production Supabase project.
- Enable PITR when available for plan.
- Apply migrations from CI, not dashboard.
- Create private storage bucket.
- Configure auth redirect URLs.
- Add production secrets to Vercel.
- Add service role key only to server-side environment.
- Create first super admin.
- Run RLS smoke tests.
- Run upload/search/chat smoke test.

## Migration Command Policy

Local:

```bash
supabase db reset
```

Staging:

```bash
supabase db push --linked
```

Production:

Use CI deployment job only. Do not apply production migrations manually through Supabase dashboard.

## Type Generation Policy

Regenerate database types after every migration change:

```bash
supabase gen types typescript --linked > src/types/database.types.ts
```

Generated types must be committed with the implementation branch.

