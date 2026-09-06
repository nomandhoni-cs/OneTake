## Context

`MyTakesView.swift` (392 lines) owns the home tab: day-grouped list, search,
row tap, context menu (Adjust/Color/Output), swipe actions, toolbar Record,
empty states, file-missing handling. All fixes stay inside this file plus
tests; model/export/Studio untouched. Pre-Implementation Gate: purpose is
"find any take and act on it in under 10 seconds"; agency preserved (nothing
forced, every destructive act confirmed); no new permissions; patterns reused
(`confirmationDialog`, `.searchScopes`, `.task(id:)`); state restored by
`@Query` (no new restoration keys — existence cache is derived, search text
stays `@State` like today).

## Goals / Non-Goals

**Goals:**
- Zero MUST violations on the home screen (confirm, purity, VoiceOver, strings).
- SHOULD fixes where native + cheap (menu grouping, trim-aware enablement, haptics, scopes).
- Every new predicate unit-tested; UI tests for reachable first-frame states.

**Non-Goals:**
- No visual redesign, no new screens, no model/schema changes.
- Badge-row AX-size reflow: accepted risk, device-QA note (HStack badges may compress at accessibility5; titles already `lineLimit(1)`).
- Seeded-media UI tests (context-menu flows need real takes; simulator has no camera) — covered by unit tests on extracted helpers instead. A drain-via-gesture e2e was attempted and dropped: XCUITest row-action queries (swipe pills, long-press menu items) don't resolve on iOS 26 and the shared test-container breaks emptiness assumptions; a flaky test is worse than none (§1.7). UI suite keeps hermetic first-frame/search/record tests.

## Decisions

- **Segment-delete confirmation over undo:** §11.2 mandates (a)-confirm for irreversible media loss. A view-level `confirmationDialog` bound to `pendingSegmentDelete: Take?` keeps context-menu buttons thin; confirm path reuses `deleteLastBladeSegment(of:)`.
- **Existence cache, not per-row tasks:** one `@State Set<Take.ID>` refreshed in `.task(id: takeIDs)` (IDs array is `Equatable`; refresh only on membership change). Row + ShareLink read the set; default `true` (files rarely vanish — avoids first-frame badge flicker for the common case).
- **Relative formatter, not manual Today/Yesterday:** `DateFormatter` with `dateStyle .medium` + `doesRelativeDateFormatting = true` returns localized "Today"/"Yesterday" and falls back to the medium date — the manual `Calendar` branch and its per-render `DateFormatter` both disappear. "Freestyle / No script" becomes `String(localized:)`.
- **Scopes replace the keyword:** `.searchScopes` (All/Reactions) is the native discoverable control (§10.1); the magic `"reaction"` string is removed so one mechanism exists (§1.4). Scope composes with title text (AND).
- **Predicates extracted as pure helpers** (`effectiveTrimLength`, `canBladeSplit`, `canDeleteLastSegment`, `matchesScope`) — testable without SwiftUI, and `body` stays declarative.
- **Haptics:** `@State haptics = HapticsService()` (Studio pattern), `.medium` on split/delete-confirm, `.light` on LUT apply.

## Risks / Trade-offs

- Removing the keyword changes behavior for anyone who discovered it: accepted (§1.6 discoverability wins; scope is strictly more visible). Spec delta documents it.
- Existence default-`true` briefly shows chevron for genuinely-missing files until the task completes: one-frame, self-correcting, preferred over badge-flicker for 99% of rows.
- `takeIDs` task key rebuilds an ID array per render (O(n) hashing, no I/O): negligible vs the `stat` syscalls it replaces.
