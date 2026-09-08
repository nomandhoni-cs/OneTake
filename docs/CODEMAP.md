# Code Map — Where Everything Lives

> Hub: [`AGENTS.md`](../AGENTS.md) → [`ARCHITECTURE.md`](ARCHITECTURE.md) (deep dive) → this map (file-by-file).

> **How to read:** `OneTake/` is the app target (auto-synced via `PBXFileSystemSynchronizedRootGroup`). `OneTakeTests/` + `OneTakeUITests/` are test targets. `openspec/` is spec-driven planning. This map lists every Swift file and what it *owns*.

## Root

| Path | Owns |
|------|------|
| `OneTake/OneTakeApp.swift` | `@main` — `ModelContainer(Schema([Script, Take, ScriptCategory]))`, `WindowGroup { ContentView().tint(.appAccent) }` |
| `OneTake/ContentView.swift` | `ENABLE_TAB_SHELL` flag, versioned onboarding gate (`completedOnboardingVersion`/`acceptedLegalVersion` → `OnboardingView`), Pro refresh on launch/foreground, `Notification.Name.showStudio`, `Route` (`studio`/`review`), `ContentView` switch, `LegacyContentView`, `ScriptLibraryView` (search, filter chips, sort `Menu`, grouped `List` by category, `CategoryFilterBar`/`CategorySectionHeader`/`ScriptRow`/`ScriptSortMode`/`CategoryFilterBar`, swipe + `contextMenu` Move to Category, `ManageCategoriesSheet` sheet, delete `confirmationDialog`), `ScriptRow` (title/body/date + `waveform` word count + `CategoryBadge`) |
| `OneTake/RootTabView.swift` | `AppTab` (`takes, scripts, studio, profile`), `RootTabView` (4-tab `TabView(sidebarAdaptable)`, per-tab `NavigationPath`s, `@SceneStorage` + `@AppStorage(studioIsRecording)` + `pendingTab`/`showLeaveConfirm` guard, `onReceive(.showStudio)` → `selectedTab=.studio` (no-op while recording)), `ScriptsTab`, `StudioTab` (2-card `StudioModePicker` + `fullScreenCover` modes), `StudioDestination`/`ReviewDestination` |
| `OneTake/Info.plist` | `NSCameraUsageDescription` etc., `NSSupportsLiveActivities` |

## Core

| Path | Owns |
|------|------|
| `Core/Persistence/Script.swift` | **`Script`**, **`ScriptCategory`**, **`Take`** (`@Model`), `relativeFilePath` ↔ `fileURL` + `trimRange` `CMTimeRange` ↔ `Double` + **`BladeSegment`** + `segmentsJSON` (source of truth) / `bladeCuts` (synced boundaries) + helpers (`split/deleteSegment/clipSegments/rangesClippedTo/syncCutsFromSegments`, `bladeSegments()`, `bladeEffectiveDuration`, `relativePath`, `documentsDirectory`), `LUTPreset` (10 cases, `displayName`, `resourceURL`, `cubeData` via loader) |
| `Core/Persistence/CadenceViewModel.swift` | `@Observable @MainActor` — `wordCount(in:)` (whitespace split), `durationSeconds(wordCount:)` @130 wpm, `formattedDuration` |
| `Core/Theme/AppTheme.swift` | `Color.appAccent` (`AccentColor` #195636), `Color.appSecondary` (`BrandSecondary` #FCCD03) |
| `Core/Export/ExportService.swift` | `ExportError`, `ciContext` (`CIContext(mtlDevice:)`), `exportPassthrough`, `exportWithLUT` (single `timeRange` + `CIFilter.colorCube`), **`exportTake(_:outputURL:)`** (multi-segment `AVMutableComposition` + `AVVideoComposition` with LUT, passthrough when Natural), `saveToPhotos`, `tempOutputURL`/`takesDirectory`/`cleanupTempFiles` |
| `Core/LUTs/LUTCubeLoader.swift` | Size-aware: `supportedDimensions` 16/32/64, `dimension(in:)` sniff (Adobe header → binary byte-count → 64), `floatData(from:dimension:)` text parser, legacy passthrough, `NSLock` cache, `filter(for:inputImage:)` → `CIColorCube` |
| `Core/LUTs/LUTThumbnailProvider.swift` | `NSCache<NSString,CGImage>` + `CIContext` singleton, `thumbnail(for:)` (masks via `CILinearGradient` blue→red → `colorCube`, Natural→gray, placeholder, **mtime invalidation**), plus **`LUTSwatchView`** (40×24, `Task.detached`, cached) |
| `Core/Audio/AudioSessionService.swift` | `@Observable` audio session + `meterTimer` (`nonisolated(unsafe)`), VU `level`, `currentRouteName` |
| `Core/Haptics/HapticsService.swift` | Prewarm, `tick`/`impact` |
| `Core/Activity/RecordingActivityService.swift` + `RecordingAttributes.swift` | `ActivityKit` Live Activity (elapsed, audio level) — attributes with red dot |

## Features

### `Features/Studio/` — Camera + Prompter

| File | Owns |
|------|------|
| `StudioView.swift` (450 lines, `// swiftlint:disable file_length type_body_length`) | Full-screen camera: `@AppStorage` resolution/frameRate/mirror/countdown/aspect/`lastScriptID` + `studioIsRecording` flag, `@State` tweak state + `isRecording`/`isPaused`/`elapsedSeconds`/`captureService` etc., `showsDismissButton` picks chrome (modal: `safeAreaInset` row with plain close/script/settings glyphs; pushed: parent bar + script/settings items), `studioContent` (camera, prompter, meter, controls, REC capsule), `isRecordingOrPaused` → `studioIsRecordingFlag` + `onChange(scenePhase)` stop on background, `confirmationDialog` for discard |
| `CameraPreviewView.swift` | `UIViewRepresentable` for `AVCaptureVideoPreviewLayer` |
| `CaptureService.swift` + `CaptureService+Delegate.swift` | `AVCaptureSession` setup, `supportedCombinations()`, `configure`, `startSession`/`stopSession`/`startRecording`/`pause`/`resume`/`stopRecording`/`finalizeSegmentsIfNeeded` |
| `PrompterView.swift` | Scrolling `Text` at `speed` |
| `CountdownView.swift` | 3-2-1 overlay |
| `VUMeterView.swift` | VU bars (`i` excluded via `// swiftlint`? single-letter) |
| `AspectMaskView.swift` | Aspect overlays |
| `TweakTrayView.swift` | Slider tray |
| `StudioSettingsSheet.swift` | Bottom sheet for resolution/frameRate/HDR/mirror/countdown/aspect/speed/font/opacity (`isReaction` hides format/HDR/aspect, shows SDR caption) + reaction bundle (`ReactionSheetBindings`): ranked Cutout (layout + outline) → 3×3 `PresenterPositionGrid` + Audio (live mic meter, volume, duck, mute) → Notes → Camera, with Done button |
| `ScriptSelectorView.swift` | `Menu` grouped by category (`@Query categories`, `groupedEntries`, `scriptButton`), `currentTitle`, `resolveTitle(for:scripts:)` static for tests. Reused by `ReactionStudioView` (freestyle default). |
| `ThermalMonitor.swift` | `shouldDowngrade` (reaction halves segmentation cadence) |
| `Reaction/ReactionModels.swift` | `StudioMode` (picker), `ReactionLayout`, `ReactionOutline`, `ReactionPresenterDefaults` (unit-rect persistence), `PresenterPosition` (9-cell grid snap presets, tested) |
| `Reaction/BackgroundSource.swift` | `BackgroundMedia`, `BackgroundSource` (`AVPlayer` playback, `loopEnabled` hold-last-frame while recording, DRM `validateVideo`), `BackgroundPickerView` (`PHPickerViewController` wrapper), `BackgroundPlayerView` (`AVPlayerLayer` representable) |
| `Reaction/PersonSegmenter.swift` | `MaskProviding` protocol + `PersonSegmenter` (`.accurate` default, runtime format via `supportedOutputPixelFormats()`, sync `mask(from:using:)` for the export job) |
| `Reaction/ReactionCompositor.swift` | `ReactionStyle`, `ReactionCanvasGeometry` (pure, tested), `ReactionCompositor` (Metal `CIContext`, `CIBlendWithMask`, circle/split, dilated-mask glow, canvas crop) |
| `Reaction/ReactionAudioMixer.swift` | `ReactionDucking` (attack 150ms/release 800ms, tested), `LookaheadDucker` (offline anticipation, tested), `PCMChunker`, `ReactionVAD`, `ReactionAudioMixer` (export settings), `PCMSampleBufferFactory` |
| `Reaction/ReactionExportJob.swift` | `ReactionExportInput/Result/Error`, `ReactionExportJob` (worker-queue reader → segment → composite → writer, `FPSProbe` downgrade, progress/cancel, temp cleanup), `VideoPass`, `BGTimeline` (loop/trim mapping, tested) |
| `Reaction/ReactionCaptureService.swift` | `@Observable @MainActor` orchestration: composes `CaptureService` movie capture, BG playback, `AudioSessionService` mic metering, export lifecycle (`PendingExport`, progress, retry/discard, space precheck, BG task), `studioIsRecording` flag source |
| `Reaction/ReactionStudioView.swift` | Full-screen reaction UI with a `safeAreaInset` chrome row (plain close/script/settings glyphs, no toolbar glass), framing preview (BG layer + live camera rect/half/fullscreen), collapsible `PrompterView` overlay (slim pill when freestyle), pending banner, `ProcessingView` flow, BG transport lock, `Take(isReaction:)` save (cutout/audio controls live in settings) |
| `Reaction/ReactionStudioComponents.swift` | Extracted bars/cards (top, paused, empty state, pending, gestures, cutout, audio, transport) — keeps view under `file_length` |
| `Reaction/ProcessingView.swift` | Export progress overlay with cancel |

### `Features/Takes/` + `Features/Review/`

| File | Owns |
|------|------|
| `MyTakesView.swift` | `@Query takes` + `scripts` for title, `searchText` + `takeScope` (`.searchScopes` All/Reactions, no magic keyword), `navigationPath`, `showStudio` (Freestyle cover, now secondary to tab), `grouped` by relative day (cached `dayFormatter`, `doesRelativeDateFormatting`), `filteredTakes` (scope AND title search), row `Button` → `MyTakesRow` (single VoiceOver element via `TakesLibrary.rowAccessibilityLabel`) + **grouped `contextMenu`** (`Section Adjust` Trim/Blade Split at Middle (trim-aware), `Section Color` LUT submenu with `LUTSwatchView` + haptic, `Section Output` Share (from existence cache), `Section Destructive` Delete Last Segment (confirmed) / Delete Take), `@State existingFiles` via `.task(id:)` (no file I/O in body), swipe Delete (confirmed)/Edit, `performDelete` (segments dir + file), `bladeSplitTake`/`deleteLastBladeSegment` (via shared `trimWindow` + haptic); pure `TakesLibrary` helpers + `TakeScope` |
| `ReviewView.swift` (652 lines, `// swiftlint:disable file_length type_body_length`) | `ScrollView` with `playerSection` (blade-aware `makePlayerItem` composition, `playheadSeconds` polled), `trimSection` (`TrimScrubberView` with `segments`/`selectedSegment`/`playheadSeconds`/`onBlade`→`splitAtPlayhead`/`onDelete`→`deleteSelectedSegment` + trim-clip + undo of segments+cuts), `lutSection` (**2-column swatch tile grid** with `LUTSwatchView` tiles + checkmark), `actionsSection` (single-line Save as New/Replace/Save to Photos/`ShareLink`), toolbar ellipsis `Menu` (same 3 sections, disabled states), helpers `loadDuration`, `reexport`/`exportAndSave` (**blade-aware** via non-mutating `rangesClippedTo` + transient `Take` + `exportTake`), `LUTSwatchView` now shared via `LUTThumbnailProvider` |
| `TrimScrubberView.swift` | Dual-handle scrubber (44pt) + **blade extensions**: `segments: [BladeSegment]`, `selectedSegment`, `playheadSeconds`, `onBlade`/`onDeleteSegment`/`onSelectSegment`, dividers at internal starts (2pt white), gap rendering, duration tags (>48pt) + `Segment i/N • m:ss` readout, playhead (yellow) clamped clear of handles, segment highlight (`yellow` stroke), handle drag, bottom `Blade` + `Delete Segment` buttons |

### `Features/Onboarding/` + `Features/Paywall/` + `Core/Paywall/` + `Core/Legal/`

| File | Owns |
|------|------|
| `OnboardingView.swift` (+`OnboardingStep`/`OnboardingFlow`) | Versioned decision flow (welcome/terms/paywall/permissions, no swipe-skip, skips where legal); pure flow helpers unit-tested |
| `TermsView.swift` (+`LegalDocumentSection`) | Terms & Privacy render + links; `accept` mode (timestamped agree) vs `readOnly` (Profile) |
| `PaywallView.swift` | Offer wall: package rows (offer-derived trial copy), purchase/restore, sheet close, auto-renewal footer, human errors |
| `Core/Paywall/StoreIDs.swift` | RC API key slot (`#warning`), entitlement `pro`, product IDs |
| `Core/Paywall/PurchasesClient.swift` | `PurchasesClient` seam + live `RevenueCatClient` + `PaywallPackage`/`TrialInfo`/`PaywallError` mapping |
| `Core/Paywall/ProEntitlementService.swift` | `isPro` cache + offering/purchase/restore intents, `customerInfoStream` listener, `MockPurchasesClient` + preview catalogs |
| `Core/Legal/LegalDocuments.swift` | Terms/Privacy URL slots (`#warning`) + bundled-md loader + legal version |
| `OneTakeApp.swift` | RevenueCat configure (keyed, DEBUG logs) + `ProEntitlementService` owner + environment |

### `Features/Workspace/`

| File | Owns |
|------|------|
| `ScriptEditorSheet.swift` | `NavigationStack` sheet: title `TextField`, `TextEditor` for body, `CategoryPickerBar` (badge + `Menu` to pick/clear/"New Category…"), bottom `SafeAreaInset` with picker bar + "Record with Prompter" |
| `ScriptCategoryViews.swift` (567 lines, `file_length` warning) | **Category kit** — `CategoryStyle` (10 styles), `CategoryIconView` (fallback dot), `CategoryChip`/`CategoryFilterBar` (chips with count, `selectedID` binding), `CategoryBadge`, `CategoryMoveMenu`/`CategoryScriptRow`, `CategoryPickerBar` (editor bar with `showNewCategoryAlert` → `ScriptCategory`), `ManageCategoriesSheet` (`@Query categories` + `scripts` for counts, create bar, `CategoryCreateBar`, `CategoryEditSheet` (draft `@State name`/`symbol` + `onSave`/`onCancel`), delete confirm), `CategoryIconView` |

### `Features/Profile/` + `Features/Settings/`

| File | Owns |
|------|------|
| `ProfileView.swift` | `Form` with `CameraDefaultsDetail`/`CountdownDetail`, `Subscription` section (OneTake Pro status → paywall sheet), `Link` to Settings, `Terms & Privacy` row (read-only `TermsView`), `Replay Welcome Tour` row (onboarding cover replay), `#Preview` with `try!` (lint disabled) |
| `StudioSettings.swift` | `Resolution`/`FrameRate`/`AspectRatio` enums, `StudioSettings` defaults |

### `AppIntents/OneTakeIntents.swift`

Siri shortcuts.

### `Assets.xcassets/` + `Resources/`

- `AccentColor` #195636, `BrandSecondary` #FCCD03, `logo.icon` (Icon Composer: 3 SVGs + `icon.json`, `ASSETCATALOG_COMPILER_APPICON_NAME = logo`)
- `Resources/*.cube` (10 LUTs: 4 legacy raw-binary 64³ + 6 Adobe SIZE-32 text from `tools/generate_luts.py`)
- `Resources/Terms.md` + `Privacy.md` (owner content pending — REPLACE BEFORE SUBMISSION)

## Tests

| Path | Covers |
|------|--------|
| `OneTakeTests/OneTakeTests.swift` | `PersistenceTests` (insert/fetch/delete, relative path, `trimRange` round-trip), `CadenceTests` (130 wpm), `TrimExportTests` (range constraints, 10 LUT presets, `ExportService` helpers), `LUTCubeLoaderTests` (text parse/reject, dimension sniff, legacy byte-identical, SIZE-32 parse, grade direction, all-preset swatches) |
| `OneTakeTests/ScriptCategoryTests.swift` | Category assign/rename/delete-nullify/duplicate, filter+sort, `CategoryStyle` mapping |
| `OneTakeTests/BladeEditingTests.swift` | Stored-range engine: split accumulation/edge/duplicate, delete-middle compaction (regression), delete first/last, sole/out-of-bounds denied, legacy cut-derivation, undo snapshot, trim clip + sliver merge + empty clear, SwiftData `segmentsJSON` round-trip, `rangesClippedTo` non-mutating |
| `OneTakeTests/TakesLibraryTests.swift` | `resolveTitle`, search, day grouping, delete cleanup, `CaptureService` pause/resume, `TakesLibraryHelperTests` (trim predicates, scopes, relative day keys, row labels) |
| `OneTakeTests/PaywallTests.swift` | Mock-client money path: offering load + annual default, purchase → pro, cancel silent, error strings, restore, cached-pro-offline, trial copy, error map, onboarding gate logic |
| `OneTakeUITests/CategoryUITests.swift` | Create script → "New Category…" → chip appears → filter (XCUITest, 28s) |
| `OneTakeUITests/FirstLaunchUITests.swift` | Versioned onboarding e2e (welcome → agree → paywall → skip → explainer → tabs), second-launch straight to tabs, teaching empty state |
| `OneTakeUITests/MyTakesUITests.swift` | Takes first-frame (title/Record/search), search-empty state (hermetic; no camera, no seeding) |
| `OneTakeUITests/PaywallUITests.swift` | Profile Pro row → paywall offline state + close, Terms row → viewer (no purchase taps) |
| `OneTakeUITests/FlowHelpers.swift` | `ensurePastOnboarding` — walks the decision flow on fresh sims, no-ops otherwise |

## Config & Tooling

| File | Purpose |
|------|---------|
| `.swiftlint.yml` | `opt_in` 18 rules, `disabled: trailing_whitespace + line_length`, `line_length` 140/180, `file_length` 400/600, `function_body_length` 50/80, `type_body_length` 300/400, `force_unwrapping`/`force_cast`/`force_try` as error, custom `prefer_observable`/`avoid_anyview`/`avoid_helper_func_view` |
| `.swiftformat` | `--swiftversion 5.9 --indent 4 --maxwidth 140 --wrapcollections before-first` etc. |
| `OneTake.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` for `OneTake/` + `OneTakeTests/`/`OneTakeUITests`, SPM `purchases-ios` 5.x → RevenueCat linked to app + test targets (`Package.resolved` committed), `ASSETCATALOG_COMPILER_APPICON_NAME = logo`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`, `SWIFT_VERSION 5.0`, `IPHONEOS_DEPLOYMENT_TARGET 18.6` |
| `openspec/` | `config.yaml` (spec-driven), `specs/` (canonical), `changes/` (6: `bottom-nav-studio-flow` 21/22, `unified-tabs-lut-preview-blade-trim` 17/17, `trim-blade-luts-pricing` 12/13 — 4.4 device QA blocked, `content-first-launch` 5/5, `my-takes-guidelines-audit` 11/11, `onboarding-terms-paywall` 16/17 — owner content/dashboard pending), `.opencode/` skills |
| `tools/generate_luts.py` | Stdlib-only generator: 6 parametric recipes (lift/gamma/gain + saturation + two-tone) baked on a 32³ lattice, R fastest, with range/count self-checks → `OneTake/Resources/*.cube` |

## Data Flow Recap (newcomer mental model)

1. **User writes Script** → `ScriptLibraryView` `openNewScriptEditor` inserts `Script(title:body:category:filterCategory)` → `ScriptEditorSheet` edits `body` → `CadenceViewModel.wordCount` → `updatedAt` → `ModelContext.save()` → `@Query` refreshes list → `CategoryFilterBar` counts update.
2. **Record** → Studio tab (`StudioView`) → `CaptureService` → `Take` file in `Takes/` → `MyTakesView` groups by day → `ReviewView` → trim + blade (`segmentsJSON` ranges) + LUT → `ExportService.exportTake` (composition) → Photos / new `Take`.
3. **Search/filter** → `filteredTakes` / `visibleScripts` (category + text + sort) → grouped `List` sections.
