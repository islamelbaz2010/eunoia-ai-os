# Credits System

Status: Draft v1

## 1. Purpose

Credits are the unified usage currency across all metered platform actions — primarily AI provider calls, but also other metered operations (e.g. WhatsApp message sends, premium report generation) — so that tenants consume a single normalized resource regardless of which underlying AI provider (OpenAI, Anthropic, Gemini) or feature performed the work.

## 2. Ledger Design

**The credit ledger is append-only and is the single source of truth for balance.** Balance is never stored as a mutable column that gets decremented in place — it is always derived from (or cached alongside, with the ledger as the reconciliation source) the sum of `credit_ledger` entries for an org.

```
credit_ledger
  id
  org_id
  delta            -- positive (grant/purchase/refund) or negative (consumption)
  balance_after    -- snapshot for fast reads, always reconcilable against sum(delta)
  reason           -- subscription_grant | credit_purchase | ai_usage | refund | expiry | adjustment
  reference_type   -- ai_message | subscription | invoice | manual
  reference_id
  created_at
```

- Every row is immutable once written. Corrections are made via a new offsetting entry (`reason = adjustment`), never by editing or deleting history — this is required for financial auditability and dispute resolution.
- `balance_after` is written transactionally with the row insert (single DB transaction, serializable on `org_id`) to prevent race conditions from concurrent debits producing an incorrect running balance.

## 3. Credit Sources

| Reason | Trigger |
|---|---|
| `subscription_grant` | Plan's monthly/annual credit allotment, granted at billing cycle start |
| `credit_purchase` | One-off top-up purchase via Stripe/Paymob |
| `refund` | Manual support-issued refund, or automatic reversal of a failed AI call that was incorrectly debited |
| `adjustment` | Manual correction by Eunoia ops, always requires an actor + reason note in `audit_log` |

## 4. Credit Consumption

- AI usage is the primary consumption path. Every AI call normalizes provider-specific cost (token-based pricing differs across OpenAI/Anthropic/Gemini and across models) into a credit cost via a **cost table** maintained centrally:

```
ai_pricing_table
  provider
  model
  credits_per_1k_input_tokens
  credits_per_1k_output_tokens
  effective_from
```

- This table is versioned by `effective_from` so historical usage can always be re-priced/audited against the rate that was actually active at call time, even if pricing changes later.
- **Debit happens atomically with usage recording**: the AI orchestration layer (SYSTEM_ARCHITECTURE.md) writes `ai_messages` and the corresponding `credit_ledger` debit in the same transaction. A successful AI response without a debit, or a debit without a successful response, must be structurally impossible.
- Failed AI calls (provider error, timeout) do not debit credits. Partial completions (e.g. a streamed response cut short by provider error) debit only for tokens actually generated, never an estimate.

## 5. Pre-Flight Credit Checks

- Before initiating an AI call, the orchestration layer checks current balance against the request's estimated maximum cost (based on max_tokens/model). If insufficient, the request is rejected with `insufficient_credits` before any provider call is made — tenants never go into an uncontrolled negative balance from a single large request.
- Small overage tolerance may apply mid-stream (since exact output length isn't known until generation completes) but is bounded and reconciled immediately after the call — never left to drift.

## 6. Rollover & Expiry

- Subscription-granted credits roll over up to a cap defined per plan (e.g. max 1x monthly allotment carried forward) to reward consistent usage without letting unused credits accumulate indefinitely as a liability.
- Purchased (top-up) credits do not expire for the life of an active subscription; they do expire a defined grace period (e.g. 90 days) after subscription cancellation, to bound long-tail liability on churned accounts.
- Expiry is applied via the scheduled Credit Expiry Sweeper (INFRASTRUCTURE.md / SYSTEM_ARCHITECTURE.md), which writes an explicit `expiry` ledger entry — expired credits are never silently dropped from a displayed balance without a corresponding ledger record.

## 7. Multi-Tenant Isolation

- `credit_ledger.org_id` is RLS-protected identically to all other tenant tables (DATABASE_ARCHITECTURE.md) — no tenant can read or infer another tenant's balance or usage history.
- Agency/enterprise tenants managing sub-accounts (future) will use a parent-child org relationship with optional credit-pooling, explicitly modeled as a separate ledger relationship — not implemented in v1, called out here so the schema isn't designed in a way that blocks it later.

## 8. Observability & Alerting

- Real-time balance is exposed via `GET /credits/balance` (API_ARCHITECTURE.md) and surfaced in the dashboard with low-balance warnings before a tenant hits zero (proactive upsell trigger for top-ups, tied into PostHog funnels).
- Any ledger write failure is alerted immediately (Sentry, high severity) — this is financial data and silent failure is unacceptable.
- Daily automated reconciliation job verifies `sum(delta)` per org matches the latest `balance_after`, flagging any drift for investigation.

## 9. Abuse Prevention

- Per-org concurrency and rate limits on AI endpoints (API_ARCHITECTURE.md) prevent a compromised API key or runaway automation from exhausting credits via a tight request loop faster than a human could notice.
- Anomalous usage spikes (e.g. 10x baseline in an hour) trigger an automatic flag for review, independent of whether the tenant has sufficient balance to pay for it.
