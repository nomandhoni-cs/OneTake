# Code Map — Where Everything Lives

> Hub: [`AGENTS.md`](../AGENTS.md) → [`ARCHITECTURE.md`](ARCHITECTURE.md) (deep dive) → this map (file-by-file).

> **How to read:** `OneTake/` is the app target (auto-synced via `PBXFileSystemSynchronizedRootGroup`). `OneTakeTests/` + `OneTakeUITests/` are test targets. `openspec/` is spec-driven planning. This map lists every Swift file and what it *owns*.

## Root

| Path | Owns |
|------|------|
| `OneTake/OneTakeApp.swift` | `@main` — `ModelContainer(Schema([Script, Take, ScriptCategory]))`, `WindowGroup { ContentView().tint(.appAccent) }` |
| `OneTake/ContentView.swift` | `ENABLE_TAB_SHELL` flag, `Notification.Name.showStudio`, `Route` (`studio`/`review`), `ContentView` switch, `LegacyContentView`, `ScriptLibraryView` (search, filter chips, sort `Menu`, grouped `List` by category, `CategoryFilterBar`/`CategorySectionHeader`/`ScriptRow`/`ScriptSortMode`/`CategoryFilterBar`, swipe + `contextMenu` Move to Category, `ManageCategoriesSheet` sheet, delete `confirmationDialog`), `ScriptRow` (title/body/date + `waveform` word count + `CategoryBadge`) |
| `OneTake/RootTabView.swift` | `AppTab` (`takes, scripts, studio, profile`), `RootTabView` (4-tab `TabView(sidebarAdaptable)`, per-tab `NavigationPath`s, `@SceneStorage` + `@AppStorage(studioIsRecording)` + `pendingTab`/`showLeaveConfirm` guard, `onReceive(.showStudio)` → `selectedTab=.studio`), `ScriptsTab`, `StudioTab`, `StudioDestination`/`ReviewDestination` |
| `OneTake/Info.plist` | `NSCameraUsageDescription` etc., `NSSupportsLiveActivities` |

## Core

| Path | Owns |
|------|------|
| `Core/Persistence/Script.swift` | **`Script`**, **`ScriptCategory`**, **`Take`** (`@Model`), `relativeFilePath` ↔ `fileURL` + `trimRange` `CMTimeRange` ↔ `Double` + `bladeCuts: [Double]?` + helpers (`normalizedBladeCuts`, `bladeSegments()`, `bladeEffectiveDuration`, `prunedBladeCuts()`, `relativePath`, `documentsDirectory`), `LUTPreset` (4 cases, `displayName`, `resourceURL`, `cubeData`) |
| `Core/Persistence/CadenceViewModel.swift` | `@Observable @MainActor` — `wordCount(in:)` (whitespace split), `durationSeconds(wordCount:)` @130 wpm, `formattedDuration` |
| `Core/Theme/AppTheme.swift` | `Color.appAccent` (`AccentColor` #195636), `Color.appSecondary` (`BrandSecondary` #FCCD03) |
| `Core/Export/ExportService.swift` | `ExportError`, `ciContext` (`CIContext(mtlDevice:)`), `exportPassthrough`, `exportWithLUT` (single `timeRange` + `CIFilter.colorCube`), **`exportTake(_:outputURL:)`** (multi-segment `AVMutableComposition` + `AVVideoComposition` with LUT, passthrough when Natural), `saveToPhotos`, `tempOutputURL`/`takesDirectory`/`cleanupTempFiles` |
| `Core/LUTs/LUTCubeLoader.swift` | `cubeDimension=64`, `data(for:)` cache, `filter(for:inputImage:)` → `CIColorCube` |
| `Core/LUTs/LUTThumbnailProvider.swift` | `NSCache<NSString,CGImage>` + `CIContext` singleton, `thumbnail(for:)` (masks via `CILinearGradient` blue→red → `colorCube`, Natural→gray, placeholder, **mtime invalidation**), plus **`LUTSwatchView`** (40×24, `Task.detached`, cached) |
| `Core/Audio/AudioSessionService.swift` | `@Observable` audio session + `meterTimer` (`nonisolated(unsafe)`), VU `level`, `currentRouteName` |
| `Core/Haptics/HapticsService.swift` | Prewarm, `tick`/`impact` |
| `Core/Activity/RecordingActivityService.swift` + `RecordingAttributes.swift` | `ActivityKit` Live Activity (elapsed, audio level) — attributes with red dot |

## Features

### `Features/Studio/` — Camera + Prompter

| File | Owns |
|------|------|
| `StudioView.swift` (450 lines, `// swiftlint:disable file_length type_body_length`) | Full-screen camera: `@AppStorage` resolution/frameRate/mirror/countdown/aspect/`lastScriptID` + `studioIsRecording` flag, `@State` tweak state + `isRecording`/`isPaused`/`elapsedSeconds`/`captureService` etc., `showsDismissButton` (hidden in tab), top bar (`StudioBackButton` + `ScriptSelectorView` + gear → `StudioSettingsSheet`), `cameraLayer` (`CameraPreviewView` or placeholder), `prompterSection`, `VUMeterView`, `recordingControls` (mic route + record/pause/resume/stop + `appSecondary` REC capsule), `isRecordingOrPaused` → `studioIsRecordingFlag` + `onChange(scenePhase)` stop on background, `confirmationDialog` for discard |
| `CameraPreviewView.swift` | `UIViewRepresentable` for `AVCaptureVideoPreviewLayer` |
| `CaptureService.swift` + `CaptureService+Delegate.swift` | `AVCaptureSession` setup, `supportedCombinations()`, `configure`, `startSession`/`stopSession`/`startRecording`/`pause`/`resume`/`stopRecording`/`finalizeSegmentsIfNeeded` |
| `PrompterView.swift` | Scrolling `Text` at `speed` |
| `CountdownView.swift` | 3-2-1 overlay |
| `VUMeterView.swift` | VU bars (`i` excluded via `// swiftlint`? single-letter) |
| `AspectMaskView.swift` | Aspect overlays |
| `TweakTrayView.swift` | Slider tray |
| `StudioSettingsSheet.swift` | Bottom sheet for resolution/frameRate/HDR/mirror/countdown/aspect/speed/font/opacity |
| `ScriptSelectorView.swift` | `Menu` grouped by category (`@Query categories`, `groupedEntries`, `scriptButton`), `currentTitle`, `resolveTitle(for:scripts:)` static for tests |
| `ThermalMonitor.swift` | `shouldDowngrade` |

### `Features/Takes/` + `Features/Review/`

| File | Owns |
|------|------|
| `MyTakesView.swift` | `@Query takes` + `scripts` for title, `searchText`, `navigationPath`, `showStudio` (Freestyle cover, now secondary to tab), `grouped` by day, `filteredTakes` (title + category name search), row `Button` → `MyTakesRow` + **grouped `contextMenu`** (`Section Adjust` Trim/Blade/Delete Last Segment, `Section Color` LUT submenu with `LUTSwatchView`, `Section Output` Share/Delete), swipe Delete/Edit, `performDelete` (segments dir + file), `bladeSplitTake`/`deleteLastBladeSegment` (mid split, `bladeCuts` sort/dedupe) |
| `ReviewView.swift` (652 lines, `// swiftlint:disable file_length type_body_length`) | `ScrollView` with `playerSection` (blade-aware `makePlayerItem` composition, `playheadSeconds` polled), `trimSection` (`TrimScrubberView` with `bladeCuts`/`selectedSegment`/`playheadSeconds`/`onBlade`→`splitAtPlayhead`/`onDelete`→`deleteSelectedSegment` + `onChange` prune + undo), `lutSection` (**swatch buttons** with `LUTSwatchView` + checkmark), `actionsSection` (Save as New/Replace/Save to Photos/`ShareLink`), toolbar ellipsis `Menu` (same 3 sections, disabled states), helpers `loadDuration`, `reexport`/`exportAndSave` (**blade-aware** via transient `Take` + `exportTake`), `LUTSwatchView` now shared via `LUTThumbnailProvider` |
| `TrimScrubberView.swift` | Dual-handle scrubber (44pt) + **blade extensions**: `bladeCuts`, `selectedSegment`, `playheadSeconds`, `onBlade`/`onDeleteSegment`/`onSelectSegment`, `normalizedCuts`, `segments`, `isBladeDisabled`/`isDeleteDisabled`, cut dividers (2pt white), playhead (yellow), segment highlight (`yellow` stroke), handle drag, bottom `Blade` + `Delete Segment` buttons + segment label |

### `Features/Workspace/`

| File | Owns |
|------|------|
| `ScriptEditorSheet.swift` | `NavigationStack` sheet: title `TextField`, `TextEditor` for body, `CategoryPickerBar` (badge + `Menu` to pick/clear/"New Category…"), bottom `SafeAreaInset` with picker bar + "Record with Prompter" |
| `ScriptCategoryViews.swift` (567 lines, `file_length` warning) | **Category kit** — `CategoryStyle` (10 styles), `CategoryIconView` (fallback dot), `CategoryChip`/`CategoryFilterBar` (chips with count, `selectedID` binding), `CategoryBadge`, `CategoryMoveMenu`/`CategoryScriptRow`, `CategoryPickerBar` (editor bar with `showNewCategoryAlert` → `ScriptCategory`), `ManageCategoriesSheet` (`@Query categories` + `scripts` for counts, create bar, `CategoryCreateBar`, `CategoryEditSheet` (draft `@State name`/`symbol` + `onSave`/`onCancel`), delete confirm), `CategoryIconView` |

### `Features/Profile/` + `Features/Settings/`

| File | Owns |
|------|------|
| `ProfileView.swift` | `Form` with `CameraDefaultsDetail`/`CountdownDetail`, `Link` to Settings, `Account` placeholder, `#Preview` with `try!` (lint disabled) |
| `StudioSettings.swift` | `Resolution`/`FrameRate`/`AspectRatio` enums, `StudioSettings` defaults |

### `AppIntents/OneTakeIntents.swift`

Siri shortcuts.

### `Assets.xcassets/` + `Resources/`

- `AccentColor` #195636, `BrandSecondary` #FCCD03, `logo.icon` (Icon Composer: 3 SVGs + `icon.json`, `ASSETCATALOG_COMPILER_APPICON_NAME = logo`)
- `Resources/*.cube` (4 LUTs)

## Tests

| Path | Covers |
|------|--------|
| `OneTakeTests/OneTakeTests.swift` | `PersistenceTests` (insert/fetch/delete, relative path, `trimRange` round-trip), `CadenceTests` (130 wpm), `TrimExportTests` (range constraints, LUT presets, `ExportService` helpers) |
| `OneTakeTests/ScriptCategoryTests.swift` | Category assign/rename/delete-nullify/duplicate, filter+sort, `CategoryStyle` mapping |
| `OneTakeTests/BladeEditingTests.swift` | Existing take single segment, blade round-trip [5,12]→3 segs, clamped/deduped, trim pruning, composition sum, thumbnail cache |
| `OneTakeTests/TakesLibraryTests.swift` | `resolveTitle`, search, day grouping, delete cleanup, `CaptureService` pause/resume |
| `OneTakeUITests/CategoryUITests.swift` | Create script → "New Category…" → chip appears → filter (XCUITest, 28s) |

## Config & Tooling

| File | Purpose |
|------|---------|
| `.swiftlint.yml` | `opt_in` 18 rules, `disabled: trailing_whitespace + line_length`, `line_length` 140/180, `file_length` 400/600, `function_body_length` 50/80, `type_body_length` 300/400, `force_unwrapping`/`force_cast`/`force_try` as error, custom `prefer_observable`/`avoid_anyview`/`avoid_helper_func_view` |
| `.swiftformat` | `--swiftversion 5.9 --indent 4 --maxwidth 140 --wrapcollections before-first` etc. |
| `OneTake.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` for `OneTake/` + `OneTakeTests/`/`OneTakeUITests`, `ASSETCATALOG_COMPILER_APPICON_NAME = logo`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`, `SWIFT_VERSION 5.0`, `IPHONEOS_DEPLOYMENT_TARGET 18.6` |
| `openspec/` | `config.yaml` (spec-driven), `specs/` (7 canonical), `changes/` (2: `bottom-nav-studio-flow` 21/22, `unified-tabs-lut-preview-blade-trim` 17/17), `.opencode/` skills |

## Data Flow Recap (newcomer mental model)

1. **User writes Script** → `ScriptLibraryView` `openNewScriptEditor` inserts `Script(title:body:category:filterCategory)` → `ScriptEditorSheet` edits `body` → `CadenceViewModel.wordCount` → `updatedAt` → `ModelContext.save()` → `@Query` refreshes list → `CategoryFilterBar` counts update.
2. **Record** → Studio tab (`StudioView`) → `CaptureService` → `Take` file in `Takes/` → `MyTakesView` groups by day → `ReviewView` → trim + blade (`bladeCuts`) + LUT → `ExportService.exportTake` (composition) → Photos / new `Take`.
3. **Search/filter** → `filteredTakes` / `visibleScripts` (category + text + sort) → grouped `List` sections.
