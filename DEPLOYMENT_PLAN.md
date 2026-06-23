# Deployment Plan

## Deployment Goal

Ship Phase 1 as a production-ready multi-tenant SaaS on Vercel + Supabase with automated migrations, repeatable setup, and clear validation gates.

## Environments

```text
local -> preview -> staging -> production
```

## Hosting

- Vercel for Next.js app and API routes.
- Supabase for Auth, Postgres, Storage, pgvector.
- VPS worker tier can be deferred until document processing/chat workload requires long-running jobs; Phase 1 may start with route-triggered processing if bounded and safe.

## Deployment Pipeline

### Pull Request

Run:

- install dependencies
- lint
- typecheck
- unit tests
- migration lint/dry-run

### Merge to Main

Run:

- apply staging migrations
- deploy staging
- run smoke tests

### Production Release

Run:

- apply production migrations
- deploy Vercel production
- run smoke tests
- verify super admin access
- verify RLS with test users

## Required Checks

```text
npm run lint
npm run typecheck
npm test
npm run env:check
supabase db reset
```

## Smoke Tests

Manual or automated:

1. Sign in.
2. Open dashboard.
3. Create organization member.
4. Create lead.
5. Create contact.
6. Add activity.
7. Upload knowledge document.
8. Process document.
9. Search knowledge.
10. Ask assistant question.
11. Open super admin organizations page.
12. Update organization status.

## Rollback Plan

Vercel:

- Promote previous deployment.

Supabase:

- Prefer forward-fix migrations.
- For destructive migrations, require backup and explicit rollback SQL before deployment.
- Phase 1 migrations should be additive only.

## Production Secrets

Store in Vercel:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
OPENAI_API_KEY
AI_DEFAULT_MODEL
APP_URL
INTERNAL_CRON_SECRET
```

Never expose:

- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `SUPABASE_DB_URL`

## Release Readiness

Phase 1 can be released when:

- All migrations apply cleanly.
- RLS tests pass.
- No service role key in browser bundle.
- Auth and tenant switching work.
- CRM CRUD works.
- Knowledge upload/search works.
- AI assistant works.
- Super admin panel works.
- Audit log records super admin status changes.

## Post-Deploy Monitoring

Track:

- auth errors
- API error rate
- document processing failures
- AI provider errors
- knowledge search latency
- database policy errors
- storage upload failures
- RLS denied events that indicate app bugs

## First Customer Deployment Rule

Do not wait for Phase 2 infrastructure. Deploy Phase 1 when the tenant foundation, CRM, knowledge base, AI assistant, dashboard, and super admin panel pass smoke tests.

