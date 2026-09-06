## Why

My Takes is the app's home surface (first tab, aggregator of all takes), but it
was built before `docs/SWIFTUI_GUIDELINES.md` existed. A line-by-line audit of
`MyTakesView.swift` against the guidelines found one MUST-level destructive
violation (menu segment-delete with no confirmation and no undo), one
MUST-level purity violation (file I/O in `body`), one MUST-level VoiceOver
violation (rows not combined), MUST-level hardcoded English strings, and a
factually wrong action label — plus SHOULD-level grouping, disabled-state,
feedback, and discoverability flaws. Production-ready means zero known
guideline violations on the home screen.

## What Changes

- Context-menu "Delete Last Segment" requires a `confirmationDialog` (irreversible media loss, §11.2).
- `FileManager.fileExists` moves out of `body` into a `.task(id:)`-refreshed `@State Set<Take.ID>` (§14.2/§13.1).
- Rows become single VoiceOver elements (combine + label + hint, §8).
- "Today"/"Yesterday" via `doesRelativeDateFormatting` (localized); "Freestyle / No script" via `String(localized:)` (§7).
- "Blade Split at Playhead" renamed "Blade Split at Middle" (it splits trim-middle, §1.6).
- Context menu regrouped: destructive items move to a bottom `Section("Destructive")` (§10.3).
- Blade/delete disabled states become trim-aware (`trimDurationSeconds`, `bladeSegments().count`, §11.1).
- Haptic confirmation on split / LUT apply / segment delete via `HapticsService` (§11.1).
- Hidden "reaction" search keyword replaced by a visible `.searchScopes` All/Reactions bar (§1.6, §10.1).
- Pure helpers extracted (`canBladeSplit`, `canDeleteLastSegment`, scope filter, day-key) with unit tests; UI tests for first-frame states.

## Capabilities

### New Capabilities
- `takes-row-a11y`: row VoiceOver contract (combine + label + hint) for the takes list.

### Modified Capabilities
- `takes-library`: context-menu contract (Adjust/Color/Output/Destructive sections, segment-delete confirmation), search scopes replacing the magic keyword, trim-aware enablement, localized day headers.

## Impact

- `OneTake/Features/Takes/MyTakesView.swift` (only production file touched).
- `OneTakeTests/TakesLibraryTests.swift` (pure-helper unit tests), `OneTakeUITests` (first-frame/search UI tests).
- No model, schema, export, or Studio changes; no new permissions or strings beyond localized existing copy.
