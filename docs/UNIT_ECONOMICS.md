# Unit Economics

Status: Build-Ready v1 — Illustrative Model
Derived from: CREDITS_SYSTEM.md, BILLING_ARCHITECTURE.md, PROJECT_DECISIONS.md

**This document models unit economics using stated assumptions, not finalized commercial pricing.** Every number below is a placeholder consistent with the architecture's mechanisms (credit ledger, markup-over-cost pricing per CREDITS_SYSTEM.md §10) and should be replaced with real provider rate cards and validated plan pricing before go-live. The purpose here is to prove the *model* is sound and break-even is reachable — not to lock specific prices.

## 1. AI Cost Model

Base assumption: blended average cost across OpenAI/Anthropic/Gemini for a mid-tier model used for typical chat/report generation (illustrative, per-million-token rates as of model authoring; replace with live provider rate cards before launch):

| Provider (illustrative model tier) | Input $/1M tokens | Output $/1M tokens |
|---|---|---|
| OpenAI (GPT-4-class) | $2.50 | $10.00 |
| Anthropic (Claude Sonnet-class) | $3.00 | $15.00 |
| Gemini (Pro-class) | $1.25 | $5.00 |
| **Blended average** (orchestration default-routing weighted ~40/30/30) | **$2.28** | **$10.00** |

These map directly into `ai_pricing_table` (DATABASE_SCHEMA_SPEC.md §4) as the cost basis, not the sale price.

## 2. Credit Conversion Model

- Defined unit: **1 credit = $0.01 of underlying AI provider cost at the blended rate**, before markup. This keeps credits intuitive for tenants (round numbers) while remaining directly traceable to `ai_pricing_table` cost basis.
- Markup target (per CREDITS_SYSTEM.md §10 resolved decision): **3x cost-plus** on credits sold to tenants — i.e. a tenant pays for credits at a rate that reflects 3x the underlying provider cost, creating a ~67% gross margin headroom on raw AI compute before accounting for platform overhead (hosting, support, payment processing fees).
- Worked conversion: 1,000 input + 1,000 output tokens at blended rates = (1,000/1,000,000 × $2.28) + (1,000/1,000,000 × $10.00) = $0.01228 raw cost ≈ **1.23 credits of raw cost** → priced to the tenant at 3x = **3.7 credits charged**, consistent with the markup model.

## 3. Estimated Cost Per Report

Modeling a representative "AI-generated marketing/business report" (e.g. a campaign plan or competitive analysis — multi-section, RAG-augmented):

| Component | Estimate | Cost |
|---|---|---|
| RAG retrieval (embedding the query + top-k chunks) | ~500 input tokens equivalent | ~$0.001 |
| Report generation (input: context + prompt) | ~6,000 tokens | 6,000/1M × $2.28 = $0.0137 |
| Report generation (output: full report) | ~3,000 tokens | 3,000/1M × $10.00 = $0.030 |
| **Total raw AI cost per report** | | **≈ $0.045** |
| Credits charged to tenant (at 1 credit = $0.01 raw, 3x markup) | | **≈ 13.5 credits**, billed at the plan's credit price |

This is the reference figure `ai_pricing_table` rows should reconcile against once real provider invoices are available — used here to validate that report-generation costs are small relative to subscription price (see §5).

## 4. Plan Pricing Assumptions (Illustrative)

| Plan | Price/mo | Credit allotment | Raw AI cost ceiling if allotment fully consumed | Implied gross margin on credit allotment alone |
|---|---|---|---|---|
| Starter | $49 | 1,000 credits | 1,000 × $0.01 / 3 ≈ $3.33 | ~93% |
| Growth | $149 | 4,000 credits | 4,000 × $0.01 / 3 ≈ $13.33 | ~91% |
| Enterprise | Custom (≥$499 floor) | Custom | Negotiated, same 3x markup floor enforced | ≥90% (floor, not ceiling) |

These figures assume full allotment consumption every cycle (worst case for margin). Actual blended margin will be higher in practice since most tenants under-consume their allotment (industry-typical SaaS usage-credit utilization is well below 100%).

## 5. Estimated Gross Margin

**Per-credit gross margin**: ~67% by construction (3x markup over raw cost) on the AI-compute component alone.

**Blended company-level gross margin** must also account for:
- Payment processing fees (Stripe ~2.9%+$0.30, Paymob comparable regionally) — applied against subscription + credit-purchase + setup-fee + agency-service revenue.
- Hosting (Vercel, Supabase, VPS) — largely fixed/step-function cost, not per-tenant variable cost, so it dilutes margin less as tenant count grows (operating leverage).
- WhatsApp/Meta messaging costs (per-conversation fees from Meta) — variable cost not yet itemized; **flagged as a missing line item** to add once integration usage patterns are known (Phase 2 deliverable).

**Estimated blended gross margin at steady state: 70-80%**, assuming AI compute remains the dominant variable cost and messaging/payment fees stay in the single-digit percentage range of revenue — consistent with typical AI-SaaS gross margins, but **not yet validated against real usage data**.

## 6. Break-Even Analysis

Illustrative fixed-cost base (monthly, pre-revenue-scale):

| Cost category | Estimated monthly |
|---|---|
| Hosting (Vercel + Supabase + VPS, all production-tier) | $500–$1,500 |
| Tooling (Sentry, PostHog, Resend) | $200–$500 |
| Founding/ops team allocation (not engineering build cost) | Excluded — assumed separately budgeted, not part of platform unit economics |
| **Total platform fixed cost (illustrative)** | **≈ $1,000/mo midpoint** |

Break-even tenant count at the midpoint, using blended ARPU:

- Assume a blended ARPU (subscription + average credit top-up) of **$120/mo** per active paying tenant (between Starter and Growth pricing, reflecting a realistic mix).
- At ~75% blended gross margin, gross profit per tenant ≈ **$90/mo**.
- Break-even tenant count ≈ $1,000 / $90 ≈ **12 paying tenants** to cover platform infrastructure costs alone (excludes setup-fee/agency revenue, which would lower this further; excludes team/operating costs, which are a separate, much larger consideration not modeled here).

**This is an infrastructure break-even, not a business break-even** — it demonstrates the platform's variable-cost model (credits priced at 3x markup) is structurally profitable per tenant from very low volume, which is the property that matters for validating the architecture's monetization design. Full business break-even (covering team, sales, support) requires a real headcount/operating budget this document does not model.

## 7. Open Items / Required Before Go-Live

1. Replace illustrative provider rates with current OpenAI/Anthropic/Gemini rate cards at time of launch (rates change; the *model* is what's being validated here, not the numbers).
2. Validate the 3x markup assumption against competitor credit pricing in target verticals (hotels, travel, medical, real estate) — it is a starting policy per CREDITS_SYSTEM.md §10, not market-tested.
3. Add WhatsApp/Meta per-conversation cost as an explicit variable-cost line once Phase 2 integration usage data exists.
4. Replace illustrative plan prices ($49/$149/Enterprise) with PROJECT_DECISIONS-approved final pricing before billing go-live.
5. Model actual team/operating cost separately to produce a true business break-even (out of scope for this architecture-stage document).
