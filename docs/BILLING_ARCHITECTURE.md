# Billing Architecture

Status: Draft v1

## 1. Billing Model Components

Per PROJECT_DECISIONS.md, billing is a composite model — this document defines how the four components coexist in one system without conflicting:

1. **Subscription** — recurring plan fee, grants a monthly/annual credit allotment (see CREDITS_SYSTEM.md).
2. **Credits (top-up)** — one-off purchases of additional credits beyond the plan allotment.
3. **Setup Fee** — one-time charge at onboarding (manual onboarding process per PROJECT_DECISIONS.md), billed once, not recurring.
4. **Agency Services** — custom/manual invoicing for services outside the self-serve product (e.g. managed campaign execution), tracked in the same `invoices` table but with a distinct `invoice_type` so reporting can separate product revenue from services revenue.

## 2. Payment Providers

- **Stripe** (primary) — international cards, subscription management, webhooks for renewal/failure/dispute events.
- **Paymob** (secondary, regional) — used where Stripe coverage/local payment methods (e.g. regional cards, wallets) are insufficient for target markets (MENA).
- A tenant is associated with exactly one active payment provider at a time per subscription — no split-provider billing for a single subscription, to avoid reconciliation complexity. Provider choice can be set at signup based on tenant region/currency.

## 3. Subscription Lifecycle

```
trial (7 days) → active → past_due → canceled
                    ↑__________________|
                  (reactivation)
```

- Trial: 7 days per PROJECT_DECISIONS.md, no payment method required to start (lower friction), but manual onboarding by the Eunoia team means trial activation is gated on a human step, not pure self-serve signup — `organizations.status` reflects this (`pending_onboarding` → `trialing` → ...).
- `active`: subscription in good standing, credits granted per cycle.
- `past_due`: payment failed; grace period (provider-default retry schedule) before access is restricted — AI/credit-consuming features are gated first, CRM/data access remains available so tenants don't lose data access during a billing hiccup.
- `canceled`: subscription ended; data retained per retention policy, credits frozen (not deleted) per the expiry rules in CREDITS_SYSTEM.md.

## 4. Local Source of Truth

- `subscriptions` and `invoices` (DATABASE_ARCHITECTURE.md) are the platform's local source of truth, but they are **derived from and reconciled against** provider state — Stripe/Paymob remain authoritative for actual payment success/failure.
- Every provider webhook event is persisted in `webhook_events` before processing (idempotent, keyed by provider event ID) so replayed/duplicate webhooks never double-apply a credit grant or double-charge.
- Nightly reconciliation job (worker tier, INFRASTRUCTURE.md) compares local subscription/invoice state against live provider state and flags drift — this catches any webhook that was missed or failed to process.

## 5. Webhook Handling

- `/webhooks/stripe` and `/webhooks/paymob` (API_ARCHITECTURE.md) verify signature, persist the raw event, return `200` immediately, and enqueue processing — never do billing state changes synchronously in the webhook handler itself.
- Processing is idempotent per `(provider, provider_event_id)` — re-delivery of the same event (common with both providers) is a no-op on the second attempt.
- Key events handled: `subscription.created`, `subscription.updated`, `subscription.deleted`, `invoice.paid`, `invoice.payment_failed`, `charge.refunded`, `charge.dispute.created`.

## 6. Setup Fee & Agency Services Invoicing

- Setup fees are recorded as a one-time `invoices` row with `invoice_type = setup_fee`, charged via the tenant's selected provider at onboarding completion (manual trigger by the Eunoia onboarding team, not automatic).
- Agency services are invoiced ad hoc — same `invoices` table, `invoice_type = agency_service`, created manually by Eunoia ops, charged via the same provider integration for unified payment history per tenant, but excluded from MRR/subscription revenue reporting.

## 7. Multi-Currency

- `invoices.currency` stored per invoice; tenant's billing currency is set at signup based on provider/region (e.g. USD/EUR via Stripe, EGP via Paymob) and does not change mid-subscription without a full migration (cancel + new subscription) to avoid proration ambiguity across providers.

## 8. Dunning & Failed Payments

- Stripe/Paymob native retry schedules are used as the first line of dunning (no custom retry logic duplicating provider behavior).
- On `invoice.payment_failed`, tenant is notified via Resend email and an in-app banner; on exhausting provider retries, subscription moves to `past_due` then `canceled` per the lifecycle above.
- Finance-role users (`organization_members.role = billing`) can view and resolve billing issues without needing CRM/AI access (API_ARCHITECTURE.md RBAC).

## 9. Refunds

- Refunds always originate from a support/ops action, never automated for completed AI usage — credits already consumed for completed AI calls are not refunded; refunds apply to the payment, with a corresponding `credit_ledger` `refund` entry only if unused granted credits are being clawed back.
- Disputes (`charge.dispute.created`) immediately flag the tenant account for manual review; access is not auto-suspended on dispute alone, only on confirmed chargeback loss, to avoid punishing tenants for in-progress disputes.

## 10. Compliance & PCI Scope

- No raw card data ever touches Eunoia infrastructure — Stripe Elements / Paymob hosted fields handle card capture entirely client-side to providers, keeping the platform out of PCI SAQ-D scope (SAQ-A applicable).
- Billing-related PII (invoices, payment metadata) classified and retained per the same `data_classification` registry referenced in DATABASE_ARCHITECTURE.md.

## 11. Reporting

- Revenue reporting separates: subscription MRR, credit top-up revenue, setup fee revenue (one-time, excluded from MRR), agency services revenue (excluded from MRR) — required given the four-part billing model, so growth metrics aren't distorted by one-time or services revenue.
