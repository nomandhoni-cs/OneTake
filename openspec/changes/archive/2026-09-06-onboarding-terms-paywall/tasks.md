## 1. RevenueCat SDK + service (`Core/Paywall/`)
- [x] 1.1 Add `purchases-ios` 5.x via SPM, link to app target, resolve + build
- [x] 1.2 `StoreIDs.swift`: RC API key slot (`#warning`), entitlement `pro`, product IDs
- [x] 1.3 `PurchasesClient` seam (live `RevenueCatClient` + `MockPurchasesClient`) + `ProEntitlementService.swift`: current offering packages, purchase, restore, `customerInfoStream` listener, cached `isPro`, preview helper

## 2. Legal (`Core/Legal/` + `Resources/Legal/`)
- [x] 2.1 `LegalDocuments.swift`: bundled md loader + upstream URL slots (`#warning` until owner content lands)
- [x] 2.2 Scaffold `Terms.md` / `Privacy.md` (marked REPLACE-BEFORE-SUBMISSION)
- [x] 2.3 `TermsView.swift`: render + links + Agree (timestamped) vs read-only modes

## 3. Paywall UI + gates
- [x] 3.1 `PaywallView.swift`: product rows (offer-derived trial copy), purchase, restore, sheet close, legal footer, human errors
- [x] 3.2 Gates: Studio record + Review export/save present paywall sheet when not Pro
- [x] 3.3 Profile "OneTake Pro" row (status → paywall) + About "Terms & Privacy" row

## 4. Onboarding v2 (`Features/Onboarding/`)
- [x] 4.1 Versioned gate in `ContentView` (`completedOnboardingVersion`, legal re-accept)
- [x] 4.2 `OnboardingView.swift`: Welcome → Terms → Trial offer → Permissions explainer (no prompts, skips where legal)

## 5. Tests
- [x] 5.1 `PaywallTests.swift` (mock client): offering loads, annual purchase → pro, user-cancel stays non-pro, restore → pro, cached pro offline, trial-copy derivation incl. no-offer fallback
- [x] 5.2 State-machine tests: gate version logic, step order/skips, paywall error mapping
- [x] 5.3 UI tests: Profile Pro row → paywall, Terms row → viewer (no purchase taps, no camera)

## 6. Gates + docs
- [x] 6.1 `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test`, `openspec validate`
- [x] 6.2 Update `docs/PRICING.md` (implemented), CODEMAP, ARCHITECTURE, AGENTS
- [ ] 6.3 OWNER TASKS (blocking submission, not code): paste Terms/Privacy text-or-URLs; create RC app + entitlement `pro` + 3 products + trial + `default` offering, paste public API key; sandbox-tester purchase pass
