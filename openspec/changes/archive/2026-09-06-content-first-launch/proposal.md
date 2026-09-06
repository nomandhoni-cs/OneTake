# Proposal: content-first launch (remove blocking onboarding)

## Problem
First launch root-switches into a 4-page `OnboardingView` carousel (splash
brand page → two teach pages → permission page) before the user ever sees the
app. Against `docs/SWIFTUI_GUIDELINES.md` §15 this fails three rules at once:

- §15 MUST "Lead with content … Never a blocking carousel of screenshots."
- §15 SHOULD "No splash/branding screens."
- §15 MUST "Permission timing … in context, immediately before the feature"
  (§16: ask only when the value is visible).

The carousel also duplicates coverage that already exists where it belongs:
`CaptureService` + `StudioView` request camera/mic when Studio opens (preview
*is* the value) with a denied-alert → Settings path, and `ExportService`
requests Photos-add at save with a human error string. Both empty states
(Scripts, Takes) already teach through `ContentUnavailableView` + action.

## Fix
Delete the gate and the flow. First frame is the usable 4-tab shell:

1. `ContentView`: drop `@AppStorage("hasSeenOnboarding")` + branch.
2. Delete `Features/Onboarding/OnboardingView.swift` (+ dir).
3. `ProfileView`: drop replay row + flag; drop the `"Sign in — coming soon"`
   dummy Account section (§1.6: every element earns its place; no auth exists).
4. Rewrite `OnboardingUITests` → `FirstLaunchUITests`: tabs on first frame,
   no onboarding buttons, teaching empty state present.

Stale `hasSeenOnboarding` keys left in existing installs are inert (never read).

## Non-goals
No new education UI (empty states already teach), no paywall/trial wall —
that lands with the monetization change per `docs/PRICING.md`.
