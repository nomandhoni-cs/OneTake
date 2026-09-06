# Store Setup — App Store Connect + RevenueCat

> One-time owner setup to take OneTake Pro live. Code side is done
> (`openspec/changes/onboarding-terms-paywall/`); this file is the human
> checklist. Keep product IDs exactly as written — the app matches them
> verbatim.

## 0. Fixed identifiers (do not change)

| What | Value |
|---|---|
| Bundle ID | `com.nomandhoni.OneTake` (mixed case — never change once set) |
| Annual | `com.nomandhoni.onetake.annual` — $12.99/yr, **7-day free trial** |
| Monthly | `com.nomandhoni.onetake.monthly` — $1.99/mo, no trial |
| Lifetime | `com.nomandhoni.onetake.lifetime` — $39.99 one-time |
| Entitlement | `pro` |
| Offering | current/default, 3 packages (`annual`, `monthly`, `lifetime`) |

Only Annual carries the trial: Apple allows one introductory offer per
subscription group, so the trial lives where it converts best. Lifetime is a
non-consumable — trials are technically impossible on it.

## 1. App Store Connect (do this first — RevenueCat imports from here)

- [ ] **Paid Apps agreement active**: App Store Connect → Agreements (Agreements,
      Tax, Banking). IAP — even sandbox — fails without it.
- [ ] **App record**: My Apps → OneTake (bundle `com.nomandhoni.OneTake`) →
      Monetization → In-App Purchases (or Features → In-App Purchases).
- [ ] **Subscription group**: + Group, reference name e.g. `OneTake Pro`.
      Annual + Monthly go in the SAME group.
- [ ] **Annual** (`com.nomandhoni.onetake.annual`): subscription, 1 Year,
      $12.99, display name e.g. `OneTake Pro Annual` + description.
      Subscription Prices → + Introductory Offer → **Free trial, 1 week**,
      new subscribers only.
- [ ] **Monthly** (`com.nomandhoni.onetake.monthly`): same group, 1 Month,
      $1.99, display name `OneTake Pro Monthly` + description.
      **No** introductory offer.
- [ ] **Lifetime** (`com.nomandhoni.onetake.lifetime`): NOT a subscription —
      separate **Non-Consumable** IAP, $39.99, e.g. `OneTake Pro Lifetime`
      + description.
- [ ] Products sit in "Ready to Submit" until the first app version review —
      normal, not a blocker for sandbox testing.
- [ ] **Sandbox tester**: Users and Access → Sandbox → Testers → + (any email
      you control + password). On device: Settings → App Store → sign OUT,
      then purchase in-app and sign in with the sandbox account at the prompt.
      Sandbox time is compressed (1-week trial ≈ 3 minutes, renews a few
      times then cancels) — ideal for testing the trial → paid handoff fast.

## 2. RevenueCat dashboard

- [ ] app.revenuecat.com → **Add app** → iOS → bundle `com.nomandhoni.OneTake`.
- [ ] **Store connection**: Project → Integrations → App Store Connect. Needs
      an ASC API key: App Store Connect → Users and Access → Integrations →
      App Store Connect API → Team Keys → generate (note Issuer ID + Key ID,
      download the `.p8` once) → upload all three to RevenueCat. Without
      this, receipts can't be verified.
- [ ] **Entitlement**: Project → Entitlements → + identifier `pro`.
- [ ] **Products**: Project → Products → + New (iOS) → enter the 3 store
      product IDs from §0 (names/prices import from ASC). Attach all three
      to the `pro` entitlement.
- [ ] **Offering**: Project → Offerings → current/default offering →
      + Package ×3: `annual` → annual product, `monthly` → monthly product,
      `lifetime` → lifetime product. Set it as Current.
- [ ] **API key**: Project settings → API keys → copy the PUBLIC Apple key
      (`appl_…`) → paste into `StoreIDs.revenueCatAPIKey` in
      `OneTake/Core/Paywall/StoreIDs.swift` (clears the build `#warning`;
      the app unlocks for real).

## 3. Legal content (blocks App Store submission)

- [ ] Paste your Terms of Service into `OneTake/Resources/Terms.md`
      (replacing the scaffold), or give me a URL and I'll set
      `LegalDocuments.termsURLString`.
- [ ] Same for Privacy Policy → `OneTake/Resources/Privacy.md` (or URL).
- [ ] Minimum coverage: camera/mic/photo-library usage, on-device storage,
      no account, contact details.

## 4. Verify end to end

- [ ] Fresh sandbox user → onboarding paywall shows real prices + "7 days
      free" on Annual only.
- [ ] Purchase Annual → trial starts → RevenueCat customer history shows
      `period_type` `TRIAL` → renews to paid after ~3 minutes.
- [ ] Restore Purchases on a second device → Pro without repaying.
- [ ] Airplane mode relaunch as Pro → record/export still open (cache).
- [ ] Decline the trial wall → library usable, Record/Export open the paywall.

## 5. Troubleshooting

| Symptom | Cause → fix |
|---|---|
| Paywall shows "Plans unavailable" | No API key pasted, or offering not Current, or no network |
| Purchase fails immediately in sandbox | Paid Apps agreement not active, or wrong product ID typo |
| Trial line missing on Annual | Intro offer not added to the Annual product in ASC |
| `pro` never flips after purchase | Products not attached to the `pro` entitlement in RC |
| Sandbox asks for real payment | Not signed out of the real App Store account on device |

## 6. Local development without the dashboard

Launch with a `-pro` argument (Scheme → Run → Arguments; DEBUG builds
only, stripped from release) to unlock gates before the key exists.
