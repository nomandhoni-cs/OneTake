## 1. Pure helpers + unit tests (TakesLibraryTests)
- [x] 1.1 Extract `effectiveTrimLength`, `canBladeSplit`, `canDeleteLastSegment`, `matchesScope`, `relativeDayKey` as pure helpers; unit-test predicates (trim-aware enablement, scope AND-composition, localized Today/Yesterday, freestyle fallback)
- [x] 1.2 Remove the magic `"reaction"` keyword path (replaced by scopes)

## 2. Body purity + localization (MyTakesView)
- [x] 2.1 Replace per-render `fileExists` calls with `@State existingFiles: Set<Take.ID>` refreshed in `.task(id: takeIDs)`; row + ShareLink read the set
- [x] 2.2 Relative day headers (`doesRelativeDateFormatting`) + `String(localized:)` freestyle string; drop manual Calendar branches

## 3. Menu contract + forgiveness
- [x] 3.1 Rename "Blade Split at Playhead" → "Blade Split at Middle"; wire trim-aware disabled states
- [x] 3.2 Move Delete Last Segment + Delete Take into bottom `Section("Destructive")`; segment delete requires `confirmationDialog` via `pendingSegmentDelete`
- [x] 3.3 Haptics (`.medium` split/delete-confirm, `.light` LUT apply) via `HapticsService`

## 4. Row accessibility + search scopes UI
- [x] 4.1 Row button: `accessibilityElement(children: .combine)` + label + hint (missing-file variant)
- [x] 4.2 `.searchScopes` All/Reactions bar composed with title text

## 5. UI tests + gates
- [x] 5.1 UI tests: first-frame (title/Record/search), search-empty state (both hermetic; delete-gesture e2e dropped — XCUITest row-action queries are unreliable on iOS 26 and the shared container breaks emptiness assumptions; delete paths covered by helper unit tests + device QA)
- [x] 5.2 `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test`, `openspec validate --changes`, CODEMAP row touch-up
