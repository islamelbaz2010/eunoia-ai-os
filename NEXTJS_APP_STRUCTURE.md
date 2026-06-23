# Next.js App Structure

## Target Stack

- Next.js App Router
- TypeScript
- Tailwind CSS
- Supabase Auth
- Supabase SSR helpers
- Zod for validation
- React Hook Form for forms
- TanStack Table for data tables
- OpenAI SDK for Phase 1 AI provider

## Directory Structure

```text
.
├── src
│   ├── app
│   │   ├── (auth)
│   │   │   ├── login
│   │   │   │   └── page.tsx
│   │   │   ├── callback
│   │   │   │   └── route.ts
│   │   │   └── logout
│   │   │       └── route.ts
│   │   ├── (app)
│   │   │   ├── layout.tsx
│   │   │   ├── dashboard
│   │   │   │   └── page.tsx
│   │   │   ├── contacts
│   │   │   │   ├── page.tsx
│   │   │   │   └── [contactId]
│   │   │   │       └── page.tsx
│   │   │   ├── leads
│   │   │   │   ├── page.tsx
│   │   │   │   └── [leadId]
│   │   │   │       └── page.tsx
│   │   │   ├── activities
│   │   │   │   └── page.tsx
│   │   │   ├── knowledge-base
│   │   │   │   ├── page.tsx
│   │   │   │   └── [documentId]
│   │   │   │       └── page.tsx
│   │   │   ├── assistant
│   │   │   │   ├── page.tsx
│   │   │   │   └── [conversationId]
│   │   │   │       └── page.tsx
│   │   │   └── settings
│   │   │       ├── organization
│   │   │       │   └── page.tsx
│   │   │       └── members
│   │   │           └── page.tsx
│   │   ├── admin
│   │   │   ├── layout.tsx
│   │   │   ├── organizations
│   │   │   │   ├── page.tsx
│   │   │   │   └── [organizationId]
│   │   │   │       └── page.tsx
│   │   │   ├── users
│   │   │   │   └── page.tsx
│   │   │   └── trials
│   │   │       └── page.tsx
│   │   └── api
│   │       └── v1
│   │           ├── contacts
│   │           ├── leads
│   │           ├── activities
│   │           ├── notes
│   │           ├── knowledge-base
│   │           ├── ai
│   │           └── admin
│   ├── components
│   ├── features
│   ├── lib
│   ├── server
│   ├── styles
│   └── types
├── supabase
│   ├── migrations
│   └── seed.sql
└── scripts
```

## Server Modules

```text
src/server
├── auth
│   ├── current-user.ts
│   ├── current-org.ts
│   ├── permissions.ts
│   └── require-role.ts
├── supabase
│   ├── browser.ts
│   ├── server.ts
│   ├── route.ts
│   └── admin.ts
├── ai
│   ├── provider.ts
│   ├── openai.ts
│   ├── embeddings.ts
│   ├── retrieval.ts
│   └── chat.ts
├── knowledge
│   ├── chunk.ts
│   ├── extract-text.ts
│   ├── process-document.ts
│   └── search.ts
├── audit
│   └── log-event.ts
└── validation
    └── schemas.ts
```

## Feature Modules

```text
src/features
├── organizations
├── members
├── contacts
├── leads
├── activities
├── notes
├── knowledge-base
├── assistant
├── dashboard
└── super-admin
```

Each feature owns:

- UI components
- API schemas
- server actions where appropriate
- table column definitions
- route-specific data loaders

## Route Groups

### `(auth)`

Public auth-only routes.

### `(app)`

Tenant application routes. Must require:

- authenticated user
- active organization membership
- valid organization status

### `admin`

Global super admin routes. Must require:

- authenticated user
- row in `super_admins`

## Middleware Responsibilities

Middleware should:

- refresh Supabase session
- redirect anonymous users away from protected app routes
- avoid doing heavy RBAC logic at the edge

Full authorization should happen server-side in loaders and route handlers.

## Initial Scripts

```json
{
  "dev": "next dev",
  "build": "next build",
  "start": "next start",
  "lint": "next lint",
  "typecheck": "tsc --noEmit",
  "db:push": "supabase db push",
  "db:reset": "supabase db reset",
  "db:types": "supabase gen types typescript --local > src/types/database.types.ts",
  "env:check": "tsx scripts/check-env.ts"
}
```

