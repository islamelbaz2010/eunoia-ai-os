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

## 5. Resolved Decision — Credit Debit Timing Under Concurrency

**Final decision: reserve-then-finalize pattern, with a per-org advisory lock guarding the reservation step.**

Sequence for every AI call:
1. **Reserve**: within a transaction holding `pg_advisory_xact_lock(hashtext(org_id::text))`, read current balance, check it covers the request's estimated max cost (based on `max_tokens`/model via `ai_pricing_table`). If sufficient, insert a `credit_ledger` row with `reason = reservation`, negative delta equal to the estimate, and commit. This serializes concurrent requests from the same org so two simultaneous calls cannot both pass the check against a balance that only covers one.
2. **Execute**: the AI provider call runs outside the lock (it may take seconds; holding a DB lock for that long would itself be a scalability risk).
3. **Finalize**: on completion, a second transaction adjusts the reservation to the actual cost — inserting an `adjustment` entry for the delta between reserved and actual (refunding the difference if actual < reserved, debiting more only up to a small bounded ceiling if actual slightly exceeds the estimate, which cannot happen under correct `max_tokens` enforcement). On provider failure, the reservation is fully reversed (`refund` entry equal to the reservation).
4. If finalize never runs (worker crash mid-call), a reconciliation sweep (same job as the daily ledger reconciliation, §8) detects orphaned `reservation` entries older than a timeout (e.g. 10 minutes) and auto-reverses them.

- Alternatives considered: (a) optimistic concurrency with retry-on-conflict — rejected, AI calls are expensive enough that retrying a whole generation due to a ledger conflict wastes both cost and latency; (b) no locking, rely on post-hoc daily reconciliation only — rejected, allows real-time overdraft between reconciliation runs, unacceptable for a credit-based monetization model; (c) distributed lock via Redis — rejected, adds a new infrastructure dependency not yet justified when Postgres advisory locks solve this at the existing system of record.
- Security/financial impact: makes overdraft structurally impossible under concurrent load from a single tenant, closing the race condition identified in self-review. Scalability impact: advisory lock is per-org, so tenants never contend with each other, only with their own concurrent requests — acceptable given AI calls are already rate-limited per org (API_ARCHITECTURE.md). Cost impact: none — uses native Postgres primitives already in use.

## 6. Pre-Flight Credit Checks

- Pre-flight checking is folded into the reserve step above — it is not a separate, unsynchronized check before a later separate debit. This removes the ambiguity flagged in self-review between "pre-flight check," "atomic debit," and "mid-stream overage tolerance," replacing all three with the single reserve → execute → finalize sequence.

## 7. Rollover & Expiry

- Subscription-granted credits roll over up to a cap defined per plan (e.g. max 1x monthly allotment carried forward) to reward consistent usage without letting unused credits accumulate indefinitely as a liability.
- Purchased (top-up) credits do not expire for the life of an active subscription; they do expire a defined grace period (e.g. 90 days) after subscription cancellation, to bound long-tail liability on churned accounts.
- Expiry is applied via the scheduled Credit Expiry Sweeper (INFRASTRUCTURE.md / SYSTEM_ARCHITECTURE.md), which writes an explicit `expiry` ledger entry — expired credits are never silently dropped from a displayed balance without a corresponding ledger record.

## 8. Multi-Tenant Isolation

- `credit_ledger.org_id` is RLS-protected identically to all other tenant tables (DATABASE_ARCHITECTURE.md) — no tenant can read or infer another tenant's balance or usage history.

### Resolved decision — agency parent-child credit pooling roadmap

**Final decision: schema is locked now (Phase 3), pooling logic ships in Phase 4 alongside Marketplace — not left undated.**

- A `org_relationships` table is added in Phase 3 (the same phase that ships Credits/Billing per ROADMAP.md): `(parent_org_id, child_org_id, relationship_type [agency_managed], credit_pool_enabled boolean, created_at)`. This costs nothing functionally in Phase 3 — `credit_pool_enabled` defaults to `false` — but guarantees the eventual pooling feature doesn't require a breaking schema migration or a ledger redesign later.
- Phase 4 (Marketplace) implements actual pooling: when enabled, a child org's credit checks (the reserve step in §5) can draw against the parent's balance via an explicit `pooled_from_org_id` reference on the reservation entry, still fully attributable per-org in the ledger for billing/reporting separation between parent and child.
- Alternatives considered: (a) build pooling now in Phase 1–3 — rejected, agencies are an important persona but pooling isn't required for any Phase 1–3 roadmap item and would delay foundational work; (b) defer indefinitely with no schema reservation — rejected per self-review finding, this is exactly the kind of deferred decision that becomes a breaking migration later; (c) implement pooling via application-layer aggregation only (no schema change) — rejected, makes per-child audit trails and billing attribution unreliable.
- Monetization impact: closes the self-review gap where the highest-LTV segment (agencies) had no scheduled path to a feature they're likely to require — now has a committed phase (4). Security impact: pooling is opt-in per relationship and still RLS-scoped per org; a child org never gains visibility into the parent's other children. Cost impact: negligible schema cost now, full feature cost deferred to Phase 4 when it can be properly scoped.

## 9. Observability & Alerting

- Real-time balance is exposed via `GET /credits/balance` (API_ARCHITECTURE.md) and surfaced in the dashboard with low-balance warnings before a tenant hits zero (proactive upsell trigger for top-ups, tied into PostHog funnels).
- Any ledger write failure is alerted immediately (Sentry, high severity) — this is financial data and silent failure is unacceptable.
- Daily automated reconciliation job verifies `sum(delta)` per org matches the latest `balance_after`, flagging any drift for investigation.

## 10. Resolved Decision — AI Pricing Inflation Protection

**Final decision: fixed markup over a quarterly-reviewed reference cost basis, with an absorbing margin buffer, instead of real-time cost pass-through.**

- Each `ai_pricing_table` entry's `credits_per_1k_*_tokens` is set using a target markup percentage (e.g. cost-plus-X%) over the provider's published per-token cost, reviewed and (if needed) updated quarterly — not on every provider price change.
- A margin buffer is maintained between the credit price charged to tenants and the actual provider cost. Routine provider price fluctuations are absorbed within this buffer without any customer-facing change. Only a sustained move that exceeds the buffer triggers a deliberate re-pricing.
- Any customer-facing credit-cost change (i.e. the number of credits a given model call consumes) is communicated with a minimum 30-day notice — tenants are never surprised by a mid-cycle change to how far their existing credit balance goes.
- Alternatives considered: (a) real-time cost pass-through pricing — rejected, produces unpredictable per-call cost for tenants and damages trust in a credit-based model; (b) fixed pricing held forever regardless of provider cost changes — rejected, erodes margin indefinitely with no mechanism to protect unit economics; (c) routing exclusively to the cheapest provider — rejected, trades quality/availability for cost in a way that contradicts the multi-provider fallback design in SYSTEM_ARCHITECTURE.md.
- Monetization impact: protects gross margin on the credit system as the core monetization mechanism, directly addressing the self-review's "no margin protection" gap. Security impact: none. Scalability impact: none — this is a pricing/finance process, not a technical scaling concern. Cost impact: requires a recurring (quarterly) finance/ops review cycle, low overhead relative to the margin risk it closes.

## 11. Abuse Prevention

- Per-org concurrency and rate limits on AI endpoints (API_ARCHITECTURE.md) prevent a compromised API key or runaway automation from exhausting credits via a tight request loop faster than a human could notice.
- Anomalous usage spikes (e.g. 10x baseline in an hour) trigger an automatic flag for review, independent of whether the tenant has sufficient balance to pay for it.
