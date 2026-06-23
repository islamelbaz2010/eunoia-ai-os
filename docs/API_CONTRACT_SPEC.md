# API Contract Specification

Status: Build-Ready v1
Derived from: API_ARCHITECTURE.md, CREDITS_SYSTEM.md, BILLING_ARCHITECTURE.md

This is the implementation-level companion to API_ARCHITECTURE.md — every endpoint below is ready to be implemented as a Next.js API route. All endpoints are under `/api/v1` and require authentication unless marked public. All authenticated endpoints resolve `org_id` server-side from the credential (never from the request body/params).

## 1. Common Conventions

- **Auth header**: `Authorization: Bearer <supabase_jwt>` (web session) or `Authorization: Bearer eun_live_...` (API key).
- **Pagination**: `?cursor=<opaque>&limit=<1-100, default 20>` on all list endpoints. Response includes `next_cursor` (null when exhausted).
- **Idempotency**: `Idempotency-Key: <client-generated-uuid>` required on `POST /ai/jobs`, `POST /credits/purchase`, `POST /billing/*`. Replays with the same key return the original response, status `200`, without re-executing the action.
- **Error envelope** (all errors):
```json
{ "error": { "code": "string", "message": "string", "request_id": "req_..." } }
```

### Standard Error Codes

| Code | HTTP Status | Meaning |
|---|---|---|
| `unauthorized` | 401 | Missing/invalid credential |
| `forbidden` | 403 | Authenticated but lacks permission (RBAC) |
| `not_found` | 404 | Resource doesn't exist or isn't visible to this org |
| `validation_error` | 422 | Request schema validation failed (includes `fields` detail array) |
| `insufficient_credits` | 402 | Org credit balance cannot cover the request |
| `plan_limit_exceeded` | 403 | Action exceeds the org's plan entitlement |
| `rate_limited` | 429 | Per-key/per-org rate limit exceeded (`Retry-After` header set) |
| `idempotency_conflict` | 409 | Same `Idempotency-Key` reused with a different request body |
| `provider_unavailable` | 502 | All configured AI providers failed for this request |
| `internal_error` | 500 | Unhandled server error |

## 2. Auth

### `POST /auth/api-keys`
- Auth: session, role `owner`/`admin`.
- Request: `{ "scopes": ["contacts:read", "ai:chat"] }`
- Response `201`: `{ "id": "uuid", "key": "eun_live_...", "scopes": [...], "created_at": "..." }` — raw key shown once, never retrievable again.
- Rate limit: 10/hour per org.

### `DELETE /auth/api-keys/{keyId}`
- Auth: session, role `owner`/`admin`.
- Response `204`.

## 3. Organizations

### `GET /orgs/{orgId}`
- Auth: any role, must match caller's `org_id`.
- Response `200`: `{ "id", "name", "industry_vertical", "locale_default", "status", "created_at" }`.

### `PATCH /orgs/{orgId}`
- Auth: role `owner`/`admin`.
- Request: `{ "name"?, "locale_default"? }` (partial)
- Response `200`: updated org object.
- Errors: `validation_error`, `forbidden`.

## 4. CRM

### `GET /contacts`
- Auth: any role.
- Query: `?cursor=&limit=&lifecycle_stage=`
- Response `200`: `{ "data": [Contact], "next_cursor": "..." }`

### `POST /contacts`
- Auth: role `owner`/`admin`/`member`.
- Request: `{ "name", "email"?, "phone"?, "locale"?, "source"?, "lifecycle_stage"?, "custom_fields"? }`
- Response `201`: Contact object.
- Errors: `validation_error`.

### `GET /contacts/{id}` / `PATCH /contacts/{id}` / `DELETE /contacts/{id}`
- Standard CRUD, same RBAC as above. `DELETE` returns `204`.

### `GET /deals`, `POST /deals`, `PATCH /deals/{id}`
- Same conventions as contacts. `POST` request: `{ "contact_id", "stage", "value"?, "currency"?, "owner_id"? }`.

### `GET /activities`, `POST /activities`
- `POST` request: `{ "contact_id"?, "type", "payload"? }`. Append-only — no `PATCH`/`DELETE`.

## 5. Knowledge Base / RAG

### `POST /knowledge-base/documents`
- Auth: role `owner`/`admin`/`member`.
- Request: `{ "source_type": "upload"|"url"|"integration", "title", "source_ref" }` (file reference for upload, URL for url type)
- Response `202`: `{ "id", "status": "pending" }` — ingestion runs async on the worker tier.
- Errors: `plan_limit_exceeded` (RAG document limit per plan), `validation_error`.

### `GET /knowledge-base/documents/{id}`
- Response `200`: `{ "id", "title", "status", "created_at" }`.

### `POST /knowledge-base/search`
- Auth: any role.
- Request: `{ "query": "string", "top_k"?: 5 }`
- Response `200`: `{ "results": [{ "chunk_id", "content", "score", "document_id" }] }`
- Rate limit: shares the AI endpoint concurrency cap (this performs an embedding call).
- Errors: `insufficient_credits` (embedding the query consumes a small credit amount).

## 6. AI

### `POST /ai/chat`
- Auth: any role.
- Request: `{ "conversation_id"?: "uuid", "message": "string", "model_preference"?: "openai"|"anthropic"|"gemini" }`
- Response: `200`, `Content-Type: text/event-stream` — SSE stream of `{ "delta": "..." }` chunks, terminated by `{ "done": true, "tokens_in", "tokens_out", "cost_credits" }`.
- Errors: `insufficient_credits` (rejected before any provider call, per CREDITS_SYSTEM.md reserve step), `provider_unavailable`, `rate_limited` (per-org AI concurrency cap).

### `POST /ai/jobs`
- Auth: any role. Requires `Idempotency-Key`.
- Request: `{ "job_type": "campaign_generation"|"report"|..., "payload": {...} }`
- Response `202`: `{ "job_id": "uuid", "status": "queued" }`
- Errors: `insufficient_credits`, `plan_limit_exceeded`, `validation_error`.

### `GET /ai/jobs/{jobId}`
- Response `200`: `{ "id", "status", "result"?, "created_at" }` — polled, or pushed via Supabase Realtime channel `org:{orgId}:jobs`.

## 7. Automations

### `GET /automations`, `POST /automations`, `PATCH /automations/{id}`, `DELETE /automations/{id}`
- Auth: role `owner`/`admin`. `POST` request: `{ "trigger", "conditions"?, "actions"?, "enabled"? }`.

## 8. Integrations

### `POST /integrations/whatsapp`
- Auth: role `owner`/`admin`.
- Request: `{ "credentials": {...} }` — encrypted server-side before storage, never echoed back.
- Response `201`: `{ "id", "provider": "whatsapp", "status": "connected" }`
- Errors: `plan_limit_exceeded` (integrations gated by plan per BILLING_ARCHITECTURE.md §2).

### `DELETE /integrations/{id}`
- Response `204`.

### `POST /integrations/meta`
- Same contract as whatsapp, `provider: "meta"`.

## 9. Credits

### `GET /credits/balance`
- Auth: any role.
- Response `200`: `{ "balance": 1234.5, "currency": "credits", "low_balance_warning": false }`

### `GET /credits/ledger`
- Auth: role `owner`/`admin`/`billing`.
- Query: `?cursor=&limit=&reason=`
- Response `200`: `{ "data": [LedgerEntry], "next_cursor": "..." }`

### `POST /credits/purchase`
- Auth: role `owner`/`admin`/`billing`. Requires `Idempotency-Key`.
- Request: `{ "credit_amount": 1000, "payment_method_id": "..." }`
- Response `202`: `{ "invoice_id": "uuid", "status": "pending" }` — credits granted on `invoice.paid` webhook confirmation, not synchronously.

## 10. Billing

### `GET /billing/subscription`
- Auth: role `owner`/`admin`/`billing`.
- Response `200`: `{ "plan_id", "plan_name", "status", "current_period_end", "provider" }`

### `POST /billing/subscription`
- Auth: role `owner`/`admin`.
- Request: `{ "plan_id", "provider": "stripe"|"paymob", "payment_method_id" }`
- Response `201`: subscription object.
- Errors: `validation_error`, `forbidden` (non-owner/admin).

### `PATCH /billing/subscription` (upgrade/downgrade)
- Request: `{ "plan_id" }`
- Response `200`: updated subscription. Proration handled by the provider, reflected on next `invoice.paid` webhook.

### `DELETE /billing/subscription` (cancel)
- Response `200`: `{ "status": "canceled", "effective_at": "..." }`

### `GET /billing/invoices`
- Auth: role `owner`/`admin`/`billing`.
- Query: `?cursor=&limit=&invoice_type=`
- Response `200`: `{ "data": [Invoice], "next_cursor": "..." }`

## 11. Webhooks (Public, Signature-Verified)

These endpoints are unauthenticated by credential but require valid provider signatures; all return `200` immediately after persisting the event, regardless of downstream processing outcome.

### `POST /webhooks/stripe`
- Verifies `Stripe-Signature` header. Invalid signature → `401`, not enqueued.
- Response `200`: `{ "received": true }`

### `POST /webhooks/paymob`
- Verifies Paymob HMAC. Invalid → `401`.
- Response `200`: `{ "received": true }`

### `POST /webhooks/whatsapp`
- Verifies WhatsApp verify token (GET challenge) / payload signature (POST). Invalid → `401`.
- Response `200`: `{ "received": true }`

### `POST /webhooks/meta`
- Verifies `X-Hub-Signature-256`. Invalid → `401`.
- Response `200`: `{ "received": true }`

## 12. Rate Limits (Default Tier — adjustable per plan)

| Scope | Limit |
|---|---|
| Per API key, general endpoints | 100 req/min |
| Per org, `/ai/chat` | 20 concurrent / 60 req/min |
| Per org, `/ai/jobs` creation | 30 req/hour |
| Per org, `/knowledge-base/search` | 60 req/min |
| Per org, `/auth/api-keys` creation | 10 req/hour |
| Webhook endpoints | not rate-limited by org (pre-auth); protected by signature verification and provider-side delivery limits |

All rate-limited responses include `Retry-After` and use error code `rate_limited`.

## 13. Auth Requirement Matrix

| Endpoint group | Session | API Key | Roles allowed |
|---|---|---|---|
| `/orgs/*` | Yes | Yes | all (read), owner/admin (write) |
| `/contacts`, `/deals`, `/activities` | Yes | Yes | owner/admin/member |
| `/knowledge-base/*` | Yes | Yes | owner/admin/member |
| `/ai/*` | Yes | Yes | owner/admin/member |
| `/automations` | Yes | Yes | owner/admin |
| `/integrations/*` | Yes | No (credential-sensitive, session only) | owner/admin |
| `/credits/*` | Yes | Yes (read only) | owner/admin/billing |
| `/billing/*` | Yes | No (payment-sensitive, session only) | owner/admin (write), billing (read) |
| `/webhooks/*` | No (signature instead) | No | n/a |
