# OneTake Architecture

> **For new contributors:** This is the map of *where code lives, where data comes from, and how it flows* — from app launch to a saved take. Read this before touching `RootTabView`, `Script.swift`, or `ExportService`.
> **Entry point:** Start at [`AGENTS.md`](../AGENTS.md) (hub) → this doc → [`CODEMAP.md`](CODEMAP.md) → `openspec/`.

## 1. Overview

OneTake is a **single-target iOS app** (no external deps) built with **SwiftUI + SwiftData + AVFoundation**. The architecture is **feature-sliced** with a thin `Core/` layer for shared services.

```
App (OneTakeApp)
 └─ Navigation Shell (RootTabView — 4-tab TabView)
     ├─ My Takes (Takes feature)
     ├─ Scripts (Workspace feature)
     ├─ Studio (Camera + Prompter)
     └─ Profile
         Core: Persistence / Capture / Export / Audio / Haptics / LUTs / Activity / Theme
```

**Principles:**
- **Offline-first:** All data in SwiftData; no network. Instant autosave via `ModelContext`.
- **Value-type state:** `@State`, `@SceneStorage`, `@AppStorage` for UI; `@Observable` for services — bodies stay pure.
- **HIG-native:** `TabView(sidebarAdaptable)` Liquid Glass on iOS 26, 44pt targets, VoiceOver order, sectioned `Menu`s, `ContentUnavailableView` for empties.
- **No magic strings:** `LUTPreset`/`Resolution`/`FrameRate` raw `String` + `CaseIterable` for pickers; `AppTheme` for colors.

## 2. Tech Stack & Constraints

| Concern | Implementation | Constraint |
|---------|--------------- |------------|
| Language | Swift 5.9, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | `IPHONEOS_DEPLOYMENT_TARGET = 18.6` (project 26.5) |
| UI | SwiftUI, `@Observable`/`@Bindable`, `NavigationStack`, `TabView`, `Menu(Section)` | HIG ≤5 tabs; Liquid Glass only on 26 |
| Persistence | SwiftData `@Model` (`Script`, `Take`, `ScriptCategory`), `@Query`, `Schema`, lightweight migration | Additive only; new optional props default `nil` |
| Media | `AVCaptureSession` (Studio), `AVMutableComposition` + `AVVideoComposition` (`CIFilter.colorCube`) for export, `AVKit.VideoPlayer`, `Photos` | `CIFilter.colorCube` needs `MTLDevice` |
| Concurrency | `async/await`, `.task`/`.onReceive`, `MainActor` | No `onAppear` fire-and-forget |
| Tooling | SwiftLint 0.65.1, SwiftFormat 0.63.0, Xcode 17, OpenSpec spec-driven | `swiftlint.yml` + `.swiftformat` at repo root |

## 3. App Lifecycle

**Entry:** `OneTakeApp.swift` (`@main`)

```swift
@main struct OneTakeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Script.self, Take.self, ScriptCategory.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }()
    var body: some Scene {
        WindowGroup { ContentView().tint(.appAccent) }
            .modelContainer(sharedModelContainer)
    }
}
```

- Single `ModelContainer` for the `WindowGroup`; previews use `modelContainer(for:inMemory:)`.
- `ContentView` is the root switch: `ENABLE_TAB_SHELL == true` → `RootTabView`, else `LegacyContentView` (single `NavigationStack` for snapshot tests).
- Global tint via `.tint(.appAccent)` (`AppTheme.swift` → `Color("AccentColor")` #195636, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`).

## 4. Navigation Shell — `RootTabView` (Unified 4-Tab)

**File:** `OneTake/RootTabView.swift` (175 lines after cleanup)

```
enum AppTab: String, CaseIterable { takes, scripts, studio, profile }

@SceneStorage("selectedTab") selectedTabRaw
@State takesPath, scriptsPath, studioPath, profilePath: NavigationPath
@AppStorage("lastScriptID") lastScriptID
@AppStorage("studioIsRecording") isStudioRecording  // published by StudioView
@State pendingTab, showLeaveConfirm
```

- `TabView(selection: selectedTab)` with `tabViewStyle(.sidebarAdaptable)` — **one pill/container**, not a custom `HStack` + overlay. Tabs:

| Tab | Content | Path |
|-----|---------|------|
| My Takes | `MyTakesView()` | `takesPath` |
| Scripts | `ScriptsTab(path: $scriptsPath)` → `ScriptLibraryView` + destinations | `scriptsPath` |
| **Studio** | `StudioTab(path: $studioPath)` → `StudioModePicker` → `fullScreenCover` (`StudioView` / `ReactionStudioView`) | `studioPath` |
| Profile | `ProfileView()` | `profilePath` |

- Per-tab `NavigationPath`s preserve stacks across tab switches.
- **Studio picker:** the Studio tab shows two mode cards (Teleprompter / Reaction, 44pt + VoiceOver); each opens full-screen via `fullScreenCover` (tab bar hidden) and dismisses back to the picker with `studioPath` preserved.
- **Deep links:** `Notification.Name.showStudio` (posted by `ScriptEditorSheet` "Record with Prompter") sets `selectedTab = .studio`; while a mode is recording the request is a no-op so the session is never interrupted. `lastScriptID` seeds `StudioView`'s selector.
- **Lifecycle guard:** `onChange(selectedTabRaw)` intercepts leaving `.studio` while `isStudioRecording == true`, reverts, and shows `confirmationDialog` ("Stay" / "Leave & Keep Paused"). Both `StudioView` and `ReactionStudioView` publish the flag via `@AppStorage("studioIsRecording")` and clear on `onDisappear`.
- **Dead code removed:** `BottomPillBar`, `StudioToolbarButton`, `StudioCover` (previously the sheet) and the trailing `HStack` overlay were deleted; Studio is now a native tab.

**Related:** `ContentView.swift` defines `ENABLE_TAB_SHELL`, `Notification.Name.showStudio`, `Route` (`studio(Script.ID)`, `review(Take.ID)`), and the legacy `ScriptLibraryView` (now category-aware).

## 5. Persistence — `Core/Persistence`

> Data contract lives in [PERSISTENCE.md](PERSISTENCE.md) (model catalog, store layout, migration rules). This section summarizes.

**Files:** `Script.swift` (models + `LUTPreset`), `Schema.swift` (`OneTakeSchemaV1` + `OneTakeMigrationPlan`), `CadenceViewModel.swift`, `AppTheme.swift`

### Models

```swift
@Model final class Script {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var createdAt, updatedAt: Date
    var category: ScriptCategory? // nullify on category delete
    @Relationship(deleteRule: .cascade, inverse: \Take.script) var takes: [Take]
}

@Model final class ScriptCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String // SF Symbol from CategoryStyle curated set
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \Script.category) var scripts: [Script]
}

@Model final class Take {
    @Attribute(.unique) var id: UUID
    var scriptID: UUID              // stable link even if Script deleted
    var relativeFilePath: String    // "Takes/<uuid>.mp4" — survives container moves
    var createdAt: Date
    var duration: TimeInterval
    var trimStartSeconds, trimDurationSeconds: Double?
    var bladeCuts: [Double]?        // DERIVED internal boundaries (kept in sync, not source of truth)
    var segmentsJSON: String?       // BladeSegment [{start,duration}] — source of truth (additive, lightweight)
    var lutPreset: String           // LUTPreset.rawValue
    var isReaction: Bool = false    // Reaction Studio composite (additive, default false)
    var backgroundAssetLocalID: String? // Photos ID of BG media (metadata only)
    var script: Script?
    var fileURL: URL { /* relative → absolute */ }
    var trimRange: CMTimeRange? { /* Double ↔ CMTime */ }
    // Blade helpers (all go through segments; cuts are re-synced):
    // split(at:) -> Int?, deleteSegment(at:) -> Bool, rangesClippedTo/clipSegments(start:end:),
    // unclippedRanges(), syncCutsFromSegments(), bladeSegments() -> [CMTimeRange], bladeEffectiveDuration
}
```

- `Take.relativeFilePath` survives app updates (container URL changes).
- `Take.segmentsJSON` is the blade feature's model: `BladeSegment {start, duration}` ranges (`String`-encoded JSON — SwiftData transformables only support plist values, so custom struct arrays persist as a JSON string; additive Optional, lightweight migration). Deletion IS compaction — kept ranges are the timeline. `bladeCuts` is re-derived via `syncCutsFromSegments()` for legacy readers. `bladeSegments()` prefers stored ranges (clipped to trim) with legacy cut-derivation fallback, and feeds `[CMTimeRange]` to composition.
- `Take.isReaction` / `backgroundAssetLocalID` follow the same additive pattern (defaults `false`/`nil`) — old stores migrate lightly; the composited MP4 is self-contained and flows through blade/trim/LUT/export unchanged.
- `Script.displayTitle` helpers, `ScriptCategory` curated icons (`CategoryStyle` in `ScriptCategoryViews.swift`).

### Cadence

`CadenceViewModel` (`@Observable @MainActor`): `wordCount(in:)` (whitespace split), `durationSeconds(wordCount:)` at 130 wpm, `formattedDuration`. Used in `ScriptEditorSheet` toolbar and `ScriptRow` subtitle.

### Theme

`AppTheme.swift`: `extension Color { static let appAccent = Color("AccentColor"), appSecondary = Color("BrandSecondary") }`. Assets: `AccentColor.colorset` #195636, `BrandSecondary.colorset` #FCCD03 (icon-derived), wired as global tint.

## 6. Features — Where Code Lives

### `Features/Takes/MyTakesView.swift` — My Takes

- `@Query(sort: \Take.createdAt, order: .reverse)` + `@Query scripts` for `resolvedTitle(for:)`
- `filteredTakes` (search over title + `script?.category?.name`)
- `grouped` by day (`Today`/`Yesterday`/date) via `Dictionary(grouping:)` + sorted keys
- Row: `MyTakesRow` (thumbnail placeholder, title, `clock` duration, `Trimmed`/`LUT`/`Reaction` badges, file-missing capsule)
- **Swipe:** trailing Delete (destructive → `confirmationDialog`), leading Edit → `Route.review`
- **Context menu (grouped):** `Section("Adjust")` Trim (push Review), Blade Split at Middle (trim-aware), `Section("Color")` LUT submenu with `LUTSwatchView` + haptic; `Section("Output")` Share (file-exists cache); `Section("Destructive")` Delete Last Segment (confirmed) + Delete Take. Same grouping is mirrored in Review's toolbar.
- Blade helpers: `bladeSplitTake(_:)` (mid of trim), `deleteLastBladeSegment(of:)` — mutate `take.bladeCuts` and `modelContext.save()`.

### `Features/Workspace/` — Scripts library + editor + categories

| File | Responsibility |
|------|----------------|
| `ScriptEditorSheet.swift` | `NavigationStack` sheet: title `TextField`, `TextEditor` for body, `CategoryPickerBar` (current badge + `Menu` to pick/clear/create), bottom `SafeAreaInset` with picker bar + "Record with Prompter" `Label`. Posts `.showStudio` notification via `lastScriptID` + `ENABLE_TAB_SHELL` branch. |
| `ScriptCategoryViews.swift` | **Category kit** — `CategoryStyle` (10 styles, `symbolName`/`icon`/`menuLabelText`), `CategoryIconView` (fallback dot), `CategoryChip`/`CategoryFilterBar`, `CategoryBadge`, `CategoryMoveMenu` (context submenu), `CategoryScriptRow`, `CategoryPickerBar` (editor bar with `showNewCategoryAlert` → `ScriptCategory(name:)`), `ManageCategoriesSheet` (create bar, edit sheet `CategoryEditSheet`, delete confirm with count, `ContentUnavailableView`), `CategorySectionHeader` |
| `ContentView.swift` (`ScriptLibraryView`) | `@Query scripts` + `@Query categories`, `searchText`, `filterCategoryID`, `sortMode` (`@AppStorage("scriptSort")`), `filteredScripts` (category + search + sort by updated/created/title), `scriptsByCategoryID`, grouped `List` with category `Section`s + `Uncategorized`, `CategoryFilterBar` in `safeAreaInset(edge:.top)` (shows "Add Category" when no categories but scripts exist), `sortMenu` (`Menu` + `Picker`), swipe Delete/Duplicate (duplicate copies `category`), context menu `CategoryMoveMenu`, delete confirmation. `ScriptRow` shows `displayTitle`, body preview, `updatedAt` + `waveform` word count/duration + `CategoryBadge`. |
| `ScriptSelectorView.swift` | Studio top-bar `Menu` for picking script. Now **grouped by category** (`@Query categories`, `groupedEntries` computed, `Section(category.name)`), with Divider + Freestyle at top. Used by `StudioView`. |

### `Features/Studio/` — Camera & Prompter

| File | Role |
|------|------|
| `StudioView.swift` | Full-screen camera. `@State` for `resolution`/`frameRate`/`aspect`/`mirror`/`countdown` (backed by `@AppStorage`), prompter tweak state (`speed`/`fontSize`/`backdropOpacity`), recording state (`isRecording`/`isPaused`/`isCountdown`/`elapsedSeconds`), services (`CaptureService`, `AudioSessionService`, `HapticsService`, `RecordingActivityService`, `ThermalMonitor`). Restores `selectedScriptID` from `initialScriptID` or `lastScriptIDStorage`. Publishes `studioIsRecording` via `@AppStorage`. Top bar: back control (`StudioBackButton` when `showsDismissButton`) + `ScriptSelectorView` + gear → `StudioSettingsSheet`. Overlays: `AspectMaskView`, paused dim, `CountdownView`, thermal banner. Bottom: `VUMeterView` + `recordingControls` + `appSecondary` REC capsule. Dismiss via `requestDismiss()` with `confirmationDialog` for active recording. |
| `CaptureService.swift` / `CaptureService+Delegate.swift` | `AVCaptureSession` lifecycle, `configure(resolution:frameRate:enableHDR:)`, `supportedCombinations()`, `start/stop/pause/resumeRecording(lockExposure:)`, `finalizeSegmentsIfNeeded`. |
| `CameraPreviewView.swift` | `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer` (production AVFoundation on every target; no preview mocks — without camera hardware the layer simply stays black). |
| `PrompterView.swift`, `CountdownView.swift`, `VUMeterView.swift`, `AspectMaskView.swift`, `TweakTrayView.swift`, `StudioSettingsSheet.swift`, `ThermalMonitor.swift`, `StudioSettings.swift` | Prompter scrolling, 3-2-1 countdown, VU meter, aspect masks, settings bottom sheet (`isReaction` hides format/HDR/aspect with SDR caption), thermal downgrade. |
| `Reaction/` (`ReactionModels`, `BackgroundSource`, `PersonSegmenter`, `ReactionCompositor`, `ReactionExportJob`, `ReactionCaptureService`, `ReactionStudioView`, `ReactionStudioComponents`, `ProcessingView`, `BackgroundPlayerView`) | Reaction Studio (capture-first): Photos BG pick (`PHPickerViewController`, DRM reject) → plain movie-file camera capture (teleprompter semantics, BG transport locked while recording) → post-capture export (`VNSequenceRequestHandler` `.accurate` + fps-probe downgrade, compositor silhouettes/circle/split + glow, offline lookahead-ducked mic/BG mix) → single MP4 `Take(isReaction:)`. Framing preview = BG layer + live camera rect (no inference during capture); progress/cancel/retry UI with temp lifecycle + free-space precheck + BG-task assertion. |

### `Features/Review/` — Review & Edit

| File | Role |
|------|------|
| `ReviewView.swift` (590 lines, `// swiftlint:disable file_length` — tracked tech debt) | `ScrollView` with `playerSection` (`VideoPlayer` with blade-aware `makePlayerItem` composition), `trimSection` (`TrimScrubberView` + preview + undo), `lutSection` (now a **2-column swatch tile grid** with `LUTSwatchView` tiles + checkmark, not a row list), `actionsSection` (Save as New / Replace / Save to Photos + `ShareLink`). State: `player`, `duration`, `trimStart/End`, `selectedLUT`, `selectedSegment`, `playheadSeconds` (polled `player.currentTime()`), `bladeUndoStack`. Helpers: `splitAtPlayhead()`, `deleteSelectedSegment()`, `pruneBladeCutsToTrim()`, `undoLastBlade()`, `loadDuration()`, `makePlayerItem(for:)` (composition when `bladeSegments.count>1`), `reexport(saveAsNew:)` and `exportAndSave()` (both **blade-aware** via transient `Take` + `ExportService.exportTake`). Toolbar ellipsis `Menu` with **3 sections** ("Adjust" Trim/Blade/Delete, "Color" LUT submenu with swatches, "Output" Save/Share) and disabled states. |
| `TrimScrubberView.swift` | Dual-handle `Capsule` scrubber with `TrimHandle` drag gestures + **blade extensions**: `bladeCuts`, `selectedSegment`, `playheadSeconds`, `onBlade`/`onDeleteSegment`/`onSelectSegment`. Renders track, selected range, **segment selection highlight** (`strokeBorder yellow`), **cut dividers** (2pt white), **playhead** (yellow), handles, and bottom `Blade` + `Delete Segment` buttons with `isBladeDisabled`/`isDeleteDisabled` + segment label. All blade params default to no-op for backward compat (`ReviewView` with old 3-arg init still compiles). |
| `LUTThumbnailProvider.swift` (`Core/LUTs/`) | `NSCache<NSString,CGImage>` + `CIContext(mtlDevice:)` singleton. `thumbnail(for:)` checks `.cube` mtime, invalidates cache, renders `baseGradient()` (`CILinearGradient` blue→red) through `CIFilter.colorCube` with the loader's sniffed dimension; Natural → neutral gray, missing data → tinted placeholder. Exported `LUTSwatchView` (40×24, async `Task.detached`, cached). |

### `Features/Profile/`, `Features/Settings/`

- `ProfileView.swift` — About/version, `CameraDefaultsDetail`, `Link` to Settings (force-unwrap disabled via lint comment).
- `StudioSettings.swift` — `Resolution`/`FrameRate`/`AspectRatio` enums, `StudioSettings` defaults, `supportedCombinations()`.

### `Core/`

| Folder | Files | Role |
|--------|-------|------|
| `Persistence` | `Script.swift` (models + `LUTPreset`), `CadenceViewModel.swift` | SwiftData + cadence math |
| `Export` | `ExportService.swift` | `exportPassthrough`, `exportWithLUT`, **new** `exportTake(_:outputURL:)` (multi-segment `AVMutableComposition` + `AVVideoComposition` with LUT; passthrough when Natural) + `PHPhotoLibrary` save |
| `LUTs` | `LUTCubeLoader.swift` (size-aware: Adobe text vs legacy raw-binary sniff, 16/32/64, `NSLock` cache, `parseAdobe`/`floatData`/`dimension(in:)`), `LUTThumbnailProvider.swift` | `.cube` loading + thumbnails |
| `Audio` | `AudioSessionService.swift` (`@Observable`, `nonisolated(unsafe) meterTimer`, level metering, `currentRouteName`) | Mic + VU |
| `Haptics` | `HapticsService.swift` | Prewarm + tick/impact |
| `Activity` | `RecordingActivityService.swift`, `RecordingAttributes.swift` | Live Activities (`elapsedSeconds`, `audioLevel`, `isRecording`) — red dot indicators |
| `Theme` | `AppTheme.swift` | `Color.appAccent` / `appSecondary` |
| `Haptics`, `Activity` |  |  |

### `AppIntents/OneTakeIntents.swift`

Siri/App Intents shortcuts (e.g., "Record with OneTake").

## 7. Data Flow — Script → Studio → Take → Review

```
User creates Script (ScriptLibraryView + Button → ModelContext.insert → @Query refresh)
  └─ Picks category (ScriptCategoryViews → script.category = cat → autosave)
  └─ "Record with Prompter" → UserDefaults lastScriptID + Notification .showStudio
       └─ RootTabView selects Studio tab → StudioTab(NavigationStack → StudioView)
            └─ StudioView restores selectedScriptID, PrompterView scrolls script.body
            └─ Record → CaptureService.startRecording(to: Takes/<uuid>.mp4)
                 └─ Take(scriptID, fileURL, duration) inserted on Stop
                      └─ MyTakesView (@Query takes) shows day-grouped row + badges
                           └─ Tap → ReviewView(take: Take) — trim + blade + LUT
                                └─ Export → AVMutableComposition (+ blade) + CIFilter.colorCube → temp mp4
                                     └─ Save as New (insert new Take) / Replace (update Take) / Save to Photos / ShareLink
```

- **File paths** are relative (`Takes/<uuid>.mp4` via `Take.relativePath`) so they survive container URL changes.
- **Deletion** cascades: `Script` delete cascades `Take`s, but deletes take files on disk first (`FileManager.removeItem`).
- **Categories** use `nullify` — scripts survive category delete as uncategorized.

## 8. Testing

| Suite | File | What it covers |
|-------|------|----------------|
| `OneTakeTests` | `OneTakeTests.swift` | Script persistence, relative paths, `CMTimeRange` round-trip, `CadenceViewModel` (130 wpm), `TrimExport` constraints, `ExportService` helpers |
| `OneTakeTests` | `ScriptCategoryTests.swift` | Category assign/rename/delete-nullify/duplicate, filter+sort logic, `CategoryStyle` mapping |
| `OneTakeTests` | `BladeEditingTests.swift` | Existing take without blade → single segment, blade round-trip (cuts [5,12] → 3 segments), clamped/deduped (0.05/19.95 pruned), trim pruning, composition sum, thumbnail cache |
| `OneTakeTests` | `TakesLibraryTests.swift` | `ScriptSelectorView.resolveTitle`, My Takes search/filter, day grouping, delete cleanup, `CaptureService` pause/resume |
| `OneTakeUITests` | `OneTakeUITests.swift` + `CategoryUITests.swift` | Launch, `testCreateCategoryFromEditorAndFilterLibrary` (create script → "New Category…" → chip appears → filter) |

Run: `xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OneTakeTests` → **62 tests passed** (Blade + Category + Takes + Reaction/Export/Position suites). UI tests: 2 passed (Reaction + Teleprompter studio flows).

## 9. Build & Tooling

- **Xcode 17 (26.5 SDK)**, `SDKROOT = iphoneos`, `IPHONEOS_DEPLOYMENT_TARGET = 18.6` (project 26.5).
- **Lint/Format:** `.swiftlint.yml` (opt-in `force_unwrapping`/`force_cast`/`force_try` as error, `file_length` 400/600, `type_body_length` 300/400, custom `prefer_observable`/`avoid_anyview`) + `.swiftformat` (4-space indent, 140 maxwidth, `wrapcollections before-first`). `swiftlint lint` → **0 errors** after recent fixes (152 warnings remain, mostly `attributes` placement and single-letter identifiers in closures). `swiftformat` → 35/40 files formatted.
- **OpenSpec:** `openspec/` spec-driven workflow. Active changes: `trim-blade-luts-pricing` (12/13 — 4.4 device taste QA blocked) and `onboarding-terms-paywall` (16/17 — owner Terms/dashboard pending); prior `unified-tabs-lut-preview-blade-trim` (17 done); `bottom-nav-studio-flow` 21/22. `openspec validate --changes` → 4 passed. `.opencode/` holds skills.
- **CI:** `xcodebuild build` succeeds on iPhone 17 Pro + iPad Pro 11-inch (M5); `swiftlint` phase runs every build (warns if not installed).

## 10. OpenSpec — Spec-Driven Changes

- `openspec/specs/` — canonical specs (7): `audio-settings-intents`, `cadence-engine`, `capture-engine`, `live-recording-hud`, `prompter-studio`, `script-workspace`, `trim-color-export`.
- `openspec/changes/trim-blade-luts-pricing/` — active: blade engine correctness (`BladeSegment` + `segmentsJSON`), timeline framing, 10 LUTs, `docs/PRICING.md`; `tasks.md` (6 groups, 13 tasks, 12 done).
- `openspec/changes/content-first-launch/` — removes the blocking onboarding carousel per guidelines §15 (content-first launch, permissions in context); `tasks.md` (3 groups, 5 tasks, all done).
- `openspec/changes/my-takes-guidelines-audit/` — home-screen hardening per guidelines (segment-delete confirm, body purity, row VoiceOver, localized days, search scopes); `tasks.md` (5 groups, 11 tasks).
- `openspec/changes/onboarding-terms-paywall/` — RevenueCat paywall (`ProEntitlementService` + gates), terms acceptance, onboarding v2; `tasks.md` (6 groups, 17 tasks, 16 done — owner content/dashboard pending).
- `openspec/changes/unified-tabs-lut-preview-blade-trim/` — `proposal.md` (BREAKING 4-tab), `design.md` (6 decisions, migration plan), `specs/` deltas (unified-tab-navigation, blade-timeline-editing, trim-color-export MODIFIED), `tasks.md` (6 groups, 17 tasks).
- `openspec/changes/bottom-nav-studio-flow/` — prior tab + takes + pause + sheet work (21/22).

## 11. Known Tech Debt (from lint)

- `ReviewView.swift` `type_body_length` (590 vs 400) and `file_length` (652 vs 600) — disabled with `// swiftlint:disable file_length type_body_length` at top; plan to split `playerSection`/`trimSection`/`lutSection`/`actionsSection` + helpers into `ReviewView+Sections.swift` / `ReviewView+Helpers.swift` (private → internal).
- `StudioView.swift` type body 422 vs 400 — disabled similarly; plan to extract `StudioRecordingControls` struct.
- `function_body_length` for `reexport(saveAsNew:)` (103 vs 80) — disabled per-function; plan to extract `prunedCutsForTrim`/`effectiveDuration` helpers.
- 152 `attributes`/`identifier_name` warnings (single-letter closure params `v`, `s`, `i`, `m` vs `min_length:2`) — low severity, tracked for next format pass.

## 12. FAQ for Newcomers

**Q: Where do I add a new tab?**
`RootTabView.swift` → `AppTab` enum + `Tab(...)` + `NavigationPath` + `selectedTab` handling. Keep HIG ≤5.

**Q: Where does a new model go?**
`Core/Persistence/Script.swift` alongside `Script`/`Take`/`ScriptCategory`, add to `Schema([...])` in `OneTakeApp` and all `modelContainer(for:)` previews + tests (17 places), rely on lightweight migration (optional prop).

**Q: Why does `Take` store `scriptID` + `script: Script?`?**
`scriptID` is stable even if `Script` is deleted; `script` relationship is optional for SwiftData graph.

**Q: How do I add a LUT?**
Add a recipe to `tools/generate_luts.py` and run it (emits Adobe SIZE-32 text to `OneTake/Resources/`), add case to `LUTPreset` (rawValue = filename), `LUTCubeThumbnailProvider` will render a swatch automatically. Legacy raw-binary 64³ cubes still load byte-identical via the loader's sniff.

**Q: How does blade export work?**
`Take.bladeSegments()` → `ExportService.exportTake(_:outputURL:)` builds `AVMutableComposition` inserting each `timeRange`, then `AVVideoComposition` with `CIFilter.colorCube` only when needed.

---

*Last updated: 2026-09-06 — during `trim-blade-luts-pricing` (BladeSegment engine, 10 LUTs, `docs/PRICING.md`). For getting started, see `GETTING_STARTED.md`; for file-by-file ownership, see `CODEMAP.md`.*
