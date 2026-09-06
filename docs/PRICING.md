# OneTake Pricing Plan

> Source: `openspec/changes/trim-blade-luts-pricing/design.md` §5, transcribed
> 2026-09-06. **Status 2026-09-06: IMPLEMENTED** via
> `openspec/changes/onboarding-terms-paywall/` (RevenueCat SDK 5.x,
> `ProEntitlementService`, `PaywallView`, record/export gates). Still open:
> owner pastes Terms/Privacy content + creates dashboard objects (§6.3).

## Recommended model: low-price paid app with a native 7-day free trial

- **Trial, not a counter:** a hand-rolled "10 free videos" counter lives
  on-device and resets on reinstall; a native trial is tracked by Apple per
  Apple ID (one trial per user, enforced by the store), needs no counting
  code, warnings UI, or "what counts" edge cases. Full features during trial.
- **Lineup (starting points to validate):** Annual **$12.99/yr** (~$1.08/mo,
  carries the 7-day free trial) + Monthly **$1.99/mo** (no trial, steers to
  annual) + **Lifetime $39.99** one-time. All are valid App Store tiers.
  Positioned well under $8–10/mo competitors: the affordable option on purpose.
  Note the volume math (~$11 net per annual sub after Apple's cut, so this
  price wins on subscriber count).
- **Flow:** onboarding → trial offer wall ("Start free 7-day trial",
  standard card-upfront Apple sheet) → full app unlocked. Decline or let it
  lapse → view-only mode (library visible, record/export locked behind lock
  affordances → paywall). Launch itself is never blocked.
- **What's included:** everything — both studios, all 10 LUTs, 4K export,
  blade/trim, Photos save + Share. No tiers-within-tiers, no LUT packs.
- **Paywall placement (future):** trial offer wall post-onboarding, lock
  affordances on record/export when unsubscribed, a "OneTake Pro" row in
  Settings with Restore Purchases. Never blocking launch or the library.
- **Future implementation shape (not built now):** RevenueCat (works without
  auth via anonymous IDs; `logIn()` aliases later) or raw StoreKit 2 —
  `Product.products(for:)`, introductory offer on Annual,
  `Transaction.currentEntitlements`, one cached `isPro` flag (offline-safe),
  entitlement checks at record + export choke points, receipt validation via
  App Store Server API only if fraud appears, plus `paywall_shown /
  trial_started / subscribed` analytics events.
- **Why subscription over paid-upfront:** trials convert; Apple Search Ads +
  editorial both favor free-download-with-trial; lifetime captures
  anti-subscription buyers who would otherwise churn at the paywall.

## Alternatives considered (all rejected)

Paid-upfront ($9.99, kills top-of-funnel for a camera app); ads (poisons a
creation flow); hand-rolled export counter (resettable, extra UI/code,
inferior to the native trial in every way); consumable credits (wrong
mental model).

## Open questions

- Final LUT display names/copy (marketing voice).
- Annual/monthly/lifetime price points — validate before App Store Connect.
- Trial length (7-day default; 3-day fallback if data shows slow conversion).

## Until the dashboard is configured

Code is implemented but the app runs view-only until the owner finishes
[`STORE_SETUP.md`](STORE_SETUP.md) (API key + dashboard objects + legal
content). Dev shortcut: launch with `-pro` (DEBUG only) to unlock gates.

## Implementation (shipped)

- **SDK:** RevenueCat `purchases-ios` 5.x via SPM (one third-party dep, ships
  its own privacy manifest). Configured in `OneTakeApp.init` from
  `StoreIDs.revenueCatAPIKey`; app stays locked (view-only) without the key.
- **Dashboard objects (owner):** entitlement `pro`; products
  `com.nomandhoni.onetake.annual` ($12.99/yr + 7-day intro),
  `.monthly` ($1.99/mo), `.lifetime` ($39.99); current offering with 3 packages.
- **Entitlement:** `ProEntitlementService` (`Core/Paywall/`) — `isPro` cached
  on-device (offline-safe), refreshed at launch/foreground/purchase/restore,
  `customerInfoStream` listener. Gates: Studio record + Review export/save
  present `PaywallView` when not Pro. Trial offer wall is onboarding step 3
  (skippable → view-only); Profile has a OneTake Pro row + Restore.
- **Sandbox QA:** create a sandbox tester (App Store Connect → Users), sign
  out of the App Store on device, purchase flows use the sandbox account;
  annual trial shows "7 days free, then $12.99/yr" derived from the offer.
  `Purchases.logLevel = .debug` in DEBUG builds.

## Dashboard setup runbook (owner)

Full checklist lives in [`STORE_SETUP.md`](STORE_SETUP.md) — App Store
Connect products + trial, RevenueCat app/entitlement/offering/key, legal
content, sandbox QA, troubleshooting. Start there; the summary below is
context only.
