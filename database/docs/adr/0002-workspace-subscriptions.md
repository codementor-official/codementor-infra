# 0002. Workspace subscriptions with immutable plan versions

- Status: accepted 2026-10-29
- Scope: migration `0042_workspace_subscriptions.sql`, learning-service `workspace-billing`,
  workspace-service quota enforcement

## Context

Study groups were unlimited. CodeMentor now sells Workspace plans (Free, Plus, Pro, Team) that cap
owned groups, members per group, total storage and file size. Two rules dominate the design:

1. **A purchase is a contract.** Editing a public plan must never change what an existing
   subscriber bought or the price they renew at.
2. **Quotas must hold under concurrency** and must never delete existing data.

Payments already exist for courses (`commerce_orders`, `commerce_payments`, VNPAY/MoMo, a
double-entry ledger). Neither provider supports tokenised recurring charges in our integration,
so every period is paid manually.

## Decision

### Ownership

| Owner | Tables |
| --- | --- |
| learning-service (commerce) | `workspace_plans`, `workspace_plan_versions`, `workspace_billing_settings`, `workspace_subscriptions`, `workspace_subscription_terms`, `workspace_orders`, `workspace_coupons`, `workspace_coupon_redemptions`, `workspace_entitlement_adjustments`; shares `commerce_payments` and the ledger |
| workspace-service | `workspace_storage_reservations` |

workspace-service reads entitlements through the SQL function
`workspace_effective_entitlements(user_id)` — a read contract like a view. It is evaluated inside
the same transaction that consumes quota, so there is no cache to go stale and no synchronous HTTP
call on the upload path.

### Plan versions are append-only

- `workspace_plans` holds presentation only (code, order, "recommended", visibility).
- `workspace_plan_versions` holds everything commercial: prices, limits, features. A version is
  `draft` until published; a trigger rejects any change to a published version.
- The version on sale is the highest published version whose `available_from` has passed, so a
  future change can be scheduled.

### A subscription is a snapshot

`workspace_subscriptions` copies the version's prices, limits and features into typed columns plus
a JSON snapshot, and a trigger makes them immutable. Enforcement reads these columns, never the
plan. Each paid period is a row in `workspace_subscription_terms`; a renewal adds a term to the
same subscription at the same contract price.

Exceptional grants are additive rows in `workspace_entitlement_adjustments` with a reason, an
author and a validity window — historical snapshots are never edited.

### State is derived from time

| State | Rule |
| --- | --- |
| `ACTIVE` | a term covers now |
| `CANCEL_SCHEDULED` | active, and the owner turned renewal off |
| `GRACE_PERIOD` | the last term ended less than `grace_days` ago and renewal was not turned off; paid limits still apply |
| `EXPIRED` / `CANCELLED` | past grace, or ended after cancellation — Free limits apply |
| `SUSPENDED` | an administrator suspended it — Free limits apply, data is kept |
| `FREE` | no open subscription |

Because enforcement evaluates timestamps, a delayed background job can never grant or remove
access by accident.

### Plan changes

- **Renewal** (same subscription, during the term or grace): a new term from
  `max(now, paid_through)` at the contract price.
- **Upgrade** (higher plan): a new subscription on the current version, effective immediately.
  The unused value of the current term is credited pro rata, in whole VND, rounded down.
- **Downgrade or billing-cycle change**: recorded as scheduled; the current subscription stops at
  the end of its paid period and the owner buys the new plan then. Nothing is charged
  automatically.

### Payments

`commerce_payments` gains `workspace_order_id`; exactly one of `order_id` and
`workspace_order_id` is set. Provider callbacks, idempotency (`commerce_provider_events`) and
reconciliation stay in one place. A successful subscription payment journals
`clearing → platform`, so the ledger stays balanced. A subscription is activated only by a
server-verified payment.

### Quotas

| Quota | Scope | Counted |
| --- | --- | --- |
| Owned groups | per owner | every group the owner owns, active or archived — archiving does not free a slot (groups are never hard-deleted) |
| Members per group | per group, using the owner's entitlements | active members, owner included; invitations do not reserve a seat, acceptance is checked |
| Storage | per owner, across owned groups | `group_documents.size_bytes` (trash included until purged) + unexpired upload reservations |
| File size | per upload | the owner's `max_upload_bytes` and the remaining storage |

Every check runs in a transaction holding an advisory lock (`ws-owner:<id>` or `ws-group:<id>`),
so two requests cannot both take the last slot. An upload reserves bytes when the URL is signed
(the size is part of the S3 signature), and the reservation becomes the document row when the
upload is confirmed.

Exceeding a limit after expiry or downgrade is an `OVER_LIMIT` condition: nothing is deleted;
only operations that consume more of the exceeded quota are refused.

## Consequences

- Existing users get Free automatically and keep all data; owners above Free limits are
  over-limit until they upgrade or clean up. No row is backfilled.
- Changing a plan always means publishing a new version.
- Recurring charges, invoices with tax data and partial refunds are out of scope until a provider
  integration supports them.
- Feature flags not yet backed by behaviour (`advanced_assignments`, `detailed_analytics`) are
  shown as "planned" and grant nothing.
