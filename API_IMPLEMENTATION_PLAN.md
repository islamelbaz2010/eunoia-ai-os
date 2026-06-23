# API Implementation Plan

## API Root

All Phase 1 routes live under:

```text
/api/v1
```

## Shared API Conventions

Every route returns:

```json
{
  "data": {},
  "request_id": "req_..."
}
```

Errors return:

```json
{
  "error": {
    "code": "string",
    "message": "string",
    "request_id": "req_..."
  }
}
```

## Request Pipeline

1. Create request id.
2. Resolve Supabase user.
3. Resolve current organization when route is tenant scoped.
4. Check RBAC.
5. Validate input with Zod.
6. Execute query through Supabase server client.
7. Return typed response.
8. Write audit event for sensitive mutations.

## Phase 1 Endpoints

### Auth

Supabase handles primary auth. Next.js owns callback/logout routes:

```text
GET /auth/callback
POST /auth/logout
```

### Current User

```text
GET /api/v1/me
GET /api/v1/me/organizations
POST /api/v1/me/current-organization
```

Purpose:

- Load signed-in user profile.
- List memberships.
- Store selected organization.

### Organizations

```text
GET /api/v1/organizations/current
PATCH /api/v1/organizations/current
GET /api/v1/organizations/current/members
```

Permissions:

- Read: all organization roles.
- Update: organization_owner.

### Contacts

```text
GET /api/v1/contacts
POST /api/v1/contacts
GET /api/v1/contacts/{contactId}
PATCH /api/v1/contacts/{contactId}
DELETE /api/v1/contacts/{contactId}
```

Permissions:

- Read: viewer and above.
- Write: analyst and above.
- Delete: executive and above.

### Leads

```text
GET /api/v1/leads
POST /api/v1/leads
GET /api/v1/leads/{leadId}
PATCH /api/v1/leads/{leadId}
DELETE /api/v1/leads/{leadId}
POST /api/v1/leads/{leadId}/convert
```

Permissions:

- Read: viewer and above.
- Write: analyst and above.
- Delete/convert: executive and above.

### Activities

```text
GET /api/v1/activities
POST /api/v1/activities
GET /api/v1/activities/{activityId}
```

Activities are append-only in Phase 1. No update/delete endpoints.

### Notes

```text
GET /api/v1/notes
POST /api/v1/notes
```

Notes are append-only in Phase 1.

### Knowledge Base

```text
GET /api/v1/knowledge-base/documents
POST /api/v1/knowledge-base/documents
GET /api/v1/knowledge-base/documents/{documentId}
DELETE /api/v1/knowledge-base/documents/{documentId}
POST /api/v1/knowledge-base/documents/{documentId}/process
POST /api/v1/knowledge-base/search
```

Upload flow:

1. Server creates signed upload URL or accepts upload route.
2. File stored in Supabase Storage.
3. `kb_documents` row inserted.
4. Processing route extracts text and chunks.
5. Embeddings stored in `kb_chunks`.

Permissions:

- Read/search: viewer and above.
- Upload/process/delete: analyst and above.

### AI Assistant

```text
GET /api/v1/ai/conversations
POST /api/v1/ai/conversations
GET /api/v1/ai/conversations/{conversationId}
POST /api/v1/ai/chat
```

Chat flow:

1. Validate message.
2. Resolve org.
3. Store user message.
4. Embed query.
5. Retrieve top knowledge chunks for org.
6. Build prompt with context.
7. Call provider.
8. Store assistant message.
9. Write usage event.
10. Return answer and context metadata.

Permissions:

- Use assistant: analyst and above.
- View prior conversations: viewer and above.

### Dashboard

```text
GET /api/v1/dashboard/summary
GET /api/v1/dashboard/leads
GET /api/v1/dashboard/activities
GET /api/v1/dashboard/usage
```

Dashboard routes aggregate tenant-scoped data only.

### Super Admin

```text
GET /api/v1/admin/organizations
GET /api/v1/admin/organizations/{organizationId}
PATCH /api/v1/admin/organizations/{organizationId}
GET /api/v1/admin/users
GET /api/v1/admin/audit-log
```

Permissions:

- Must be in `super_admins`.

All status/trial mutations write audit log entries.

## Validation Schemas

Create shared Zod schemas:

```text
src/server/validation
├── contacts.ts
├── leads.ts
├── activities.ts
├── notes.ts
├── knowledge-base.ts
├── ai.ts
├── organizations.ts
└── admin.ts
```

## Pagination

Use cursor pagination for high-volume lists:

- contacts
- leads
- activities
- notes
- conversations
- documents
- audit log

Initial implementation may use `created_at` + `id` cursor.

## Rate Limiting

Phase 1 must include simple rate limiting before AI and knowledge search are exposed:

- Per user for `/api/v1/ai/chat`
- Per organization for `/api/v1/knowledge-base/search`
- Per organization for document processing

Implementation options:

- Supabase table-backed limiter for first release.
- Upstash/Redis can be added later if needed.

## Idempotency

Phase 1 does not include billing or credit purchase endpoints, but document processing and chat retry safety should be handled by stable resource ids:

- document processing is idempotent per `document_id`
- chat messages are stored once per request when client sends `client_message_id`

Advanced idempotency table can wait until billing/credits.

