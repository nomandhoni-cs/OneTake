## Context

`content-first-launch` removed the blocking carousel; permissions already ask
in context (`CaptureService` + `StudioView` alert, `ExportService` Photos-add).
What remains missing: legal acceptance, any monetization (`docs/PRICING.md`
is still docs-only), and a permissions explainer. This change adds all three
as decision surfaces, not a tutorial. RevenueCat (not raw StoreKit 2) per
owner direction — anonymous IDs out of the box, server-side entitlement
truth, dashboard-managed offerings.

## Goals / Non-Goals

**Goals:**
- Legally-binding Terms & Privacy acceptance (blocking, timestamped, re-accessible).
- Working paywall: 3 products, 7-day trial on Annual, purchase, restore, offline-safe `isPro`, record/export gates.
- Guidelines-compliant onboarding: versioned, skippable where legal, zero system prompts inside it.
- Real test coverage: mock-client purchase/restore unit tests, state-machine tests, deterministic UI tests.

**Non-Goals:**
- Analytics events (`paywall_shown` etc.) — no infra exists; deferred.
- Server-side receipt validation — per pricing plan, only if fraud appears.
- Legal copy itself — owner provides Terms/Privacy text or URLs (tracked task; build `#warning` until set).
- Creating products + offering in the RevenueCat dashboard — owner step (tracked task); manual sandbox QA documented.

## Decisions

- **RevenueCat SDK 5.x via SPM + `@Observable` service:** `ProEntitlementService`
  (`Core/Paywall/`) sits over a `PurchasesClient` seam (live `RevenueCatClient`
  + `MockPurchasesClient` for tests): current offering's packages, purchase,
  restore, and a `customerInfoStream` listener started at init. `Purchases`
  configured once in `OneTakeApp.init` (RC SwiftUI doc, Option 1) when the API
  key is set; `isPro` = `customerInfo.entitlements["pro"].isActive`, cached in
  `@AppStorage` (offline-safe); refreshed at launch, foreground, and after
  every purchase/restore. User-cancelled purchases are silent (no error UI).
- **Dashboard objects** (owner tasks): entitlement `pro`, products
  `com.nomandhoni.onetake.{annual,monthly,lifetime}` ($12.99/yr + 7-day intro,
  $1.99/mo, $39.99 lifetime), `default` offering with 3 packages, public API
  key in `StoreIDs` (`#warning` until set — service stays locked/non-pro
  without it, never crashes).
- **Gates present the paywall, never an alert:** Studio record and Review
  export check `isPro` at the action entry and present `PaywallView` as a
  sheet. Launch and library are never blocked (§15).
- **Versioned onboarding:** `completedOnboardingVersion < currentOnboarding(2)`
  shows the flow; `acceptedLegalVersion < currentLegal(1)` forces a terms-only
  pass later. Steps: Welcome → Terms (blocking) → Trial offer (skippable →
  view-only) → Permissions explainer (no prompts) → shell.
- **Terms screen:** bundled markdown (owner replaces) + upstream URL links when
  set; Agree records ISO timestamp. Profile About re-opens it read-only.
- **Trial copy from the package:** "7 days free" renders only when
  `storeProduct.introductoryDiscount?.paymentMode == .freeTrial`; RC `Error`
  maps to human strings (§11.3), never raw errors. Previews use RC
  `TestStoreProduct`/`Offering` (per RC SwiftUI docs) — no live account needed.
- **Previews:** every touched preview injects `.environment(ProEntitlementService.previewUnlocked)`; paywall previews build on `TestStoreProduct`.

## Risks / Trade-offs

- Entitlement truth lives on RC servers (`CustomerInfo`): no local receipt
  parsing, so nothing to spoof client-side; offline falls back to the cache.
- Trial ultimately enforced by the RC/ASC intro-offer config; mismatch shows
  fallback copy — mitigated by deriving copy from the discount object.
- Terms content pending: Agree screen ships against scaffold files with
  `#warning`; App Store submission blocked on the owner task, stated in tasks.
- No `.storekit` file: RevenueCat validates against its dashboard/ASC, not
  local config; manual QA uses sandbox testers (documented step).
