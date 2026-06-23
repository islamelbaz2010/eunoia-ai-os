# Security Checklist

## Authentication

- Supabase Auth is the only Phase 1 identity provider.
- Protected routes require a valid session.
- Auth callback validates redirect destinations.
- Logout clears session cookies.
- Production requires email confirmation.

## Tenant Isolation

- Every tenant-owned table has `org_id`.
- Every tenant-owned table has RLS enabled.
- All application queries resolve organization server-side.
- Client-provided `org_id` is ignored or rejected.
- RLS tests cover cross-tenant read and write attempts.

## RBAC

Roles:

- `super_admin`
- `organization_owner`
- `executive`
- `analyst`
- `viewer`

Requirements:

- RBAC enforced in route handlers and server actions.
- UI hiding is convenience only, never security.
- Viewer has no write access.
- Super admin access requires `super_admins` row.
- Organization members cannot access `/admin`.

## Service Role Key

- Service role key is server-only.
- Never import service client into client components.
- Never expose service role key in browser bundle.
- Use service role only for controlled admin/bootstrap operations.

## AI and RAG Safety

- Retrieval queries must filter by `org_id`.
- RLS must also protect `kb_chunks`.
- AI prompt construction must not include cross-tenant data.
- Uploaded document processing must validate file type and size.
- Store extracted text only in tenant-scoped rows.
- Do not let users override system prompts through document content.

## Storage

- Knowledge document bucket is private.
- Uploads use signed URLs or server-mediated upload.
- Object path includes organization id.
- Delete document metadata and storage object together through server action.

## API Security

- Validate all input with Zod.
- Return structured errors only.
- Include request id in all responses.
- Rate limit AI chat and knowledge search.
- Audit sensitive admin mutations.
- No unauthenticated Phase 1 API routes except auth callback/logout mechanics.

## Data Protection

- PII fields are tenant scoped.
- Audit log is append-only.
- Notes and activities are append-only unless a deletion requirement is explicitly implemented.
- Medical clinic data requires stricter retention/compliance before launch in that vertical.

## Operational Security

- Separate staging and production Supabase projects.
- No production data in preview.
- Rotate provider keys independently.
- Store secrets only in Vercel/Supabase secret stores.
- CI must not print secrets.

## Launch Gate

Before first customer:

- RLS tests pass.
- Auth smoke test passes.
- Super admin guard passes.
- File upload smoke test passes.
- Knowledge search returns only same-org chunks.
- AI chat stores messages and usage event.
- Viewer write attempts fail.

