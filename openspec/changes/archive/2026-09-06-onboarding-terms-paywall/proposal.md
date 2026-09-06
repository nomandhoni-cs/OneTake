## Why

The owner needs three things the app lacks: legally-binding Terms & Privacy
acceptance before use, a working paywall implementing the approved
`docs/PRICING.md` lineup (Annual $12.99 with 7-day trial / Monthly $1.99 /
Lifetime $39.99), and a permissions story. The previous change
(`content-first-launch`) deleted the old carousel for good guideline reasons —
this change brings onboarding back as decision surfaces (agree, subscribe,
understand), not a tutorial, with system permission prompts staying in
context per guidelines §15/§16.

## What Changes

- New `onboarding-v2` flow (versioned key, re-prompts on future T&C bumps):
  Welcome (value props) → Terms & Privacy (blocking accept, timestamped) →
  Trial offer wall (skippable → view-only) → Permissions explainer (no system
  prompts; requests stay in Studio/save) → shell.
- New `paywall` capability: RevenueCat SDK (`purchases-ios` 5.x via SPM) —
  `ProEntitlementService` over a `PurchasesClient` seam (offerings/packages,
  purchase, restore, `customerInfoStream` listener, offline-safe cached
  `isPro`), reusable `PaywallView` (onboarding step, sheet from gates,
  Profile row), record + export entitlement gates presenting the paywall.
- New `legal-acceptance` capability: bundled Terms/Privacy documents with
  configurable upstream URLs, acceptance record, in-app re-access from
  Profile; content slots pending owner text (build `#warning`, tracked task).
- Product IDs `com.nomandhoni.onetake.{annual,monthly,lifetime}`, entitlement
  `pro`, `default` offering — created in the RevenueCat dashboard (mirrors App
  Store Connect); public RC API key in `StoreIDs` (tracked task). Sandbox
  testing via RC dashboard test users; no `.storekit` file (RC server-side).

## Capabilities

### New Capabilities
- `onboarding-v2`: versioned first-run decision flow (welcome/terms/paywall/explainer).
- `paywall`: RevenueCat offerings/packages, purchase, restore, entitlement cache, gates.
- `legal-acceptance`: terms/privacy presentation, acceptance record, re-access.

### Modified Capabilities
- (none — prior change removed onboarding entirely; this adds new capabilities)

## Impact

- New: `Core/Paywall/`, `Core/Legal/`, `Features/Paywall/PaywallView.swift`,
  `Features/Onboarding/OnboardingView.swift` (v2), `Resources/Legal/*.md`,
  `PaywallTests.swift` (mock-client; `TestStoreProduct` previews per RC docs).
- Modified: `OneTakeApp` (service owner + environment), `ContentView` (versioned
  gate), `StudioView` (record gate), `ReviewView` (export gates), `ProfileView`
  (Pro + Terms rows), `MyTakesUITests`/`FirstLaunchUITests` (flow coverage).
- One third-party dep: RevenueCat SDK via SPM (App Store–standard for IAP;
  ships its own privacy manifest). No analytics events yet
  (no infra — deferred, noted in design).
