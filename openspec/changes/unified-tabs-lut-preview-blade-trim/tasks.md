## 1. Unified Tab Navigation (Studio as 4th Tab)

- [x] 1.1 Extend `AppTab` in `RootTabView.swift` to `case studio` with title "Studio" and `video`/`video.fill` symbols; add `studioPath: NavigationPath` @State and `@SceneStorage` persistence
- [x] 1.2 Replace overlay `HStack` floating circle + `fullScreenCover`/`StudioCover` with 4th `Tab("Studio", systemImage: video.*, value: .studio) { StudioTab }` inside the same `TabView(sidebarAdaptable)`; remove `BottomPillBar` external HStack and verify single pill/container
- [x] 1.3 Migrate Studio lifecycle to tab visibility: start `CaptureService` on `onAppear` when `selectedTab == .studio`, stop on `onDisappear`/`scenePhase.background`, and guard `onChange(selectedTab)` with `confirmationDialog` when leaving mid-recording
- [x] 1.4 Reroute deep links: `onReceive(.showStudio)` and editor "Record with Prompter" now set `selectedTab = .studio` and push `initialScriptID` via `studioPath` (preserve `lastScriptID`); remove sheet-presentation path and verify VoiceOver order My Takes → Scripts → Studio → Profile with 44pt targets

## 2. LUT Preview Swatches

- [x] 2.1 Add `LUTCubeThumbnailProvider` (NSCache<NSString, CGImage>, `CIContext(mtlDevice:)` singleton) that renders each `LUTPreset` 40×24 swatch by applying `CIFilter.colorCube` to a neutral gradient `CIImage`; Natural returns neutral gray without filter, missing cubeData returns tinted placeholder
- [x] 2.2 Update `ReviewView` LUT picker rows to show `Image(cgImage)` swatch + `displayName` in `HStack` with cached async loading and `.cube` mtime invalidation; verify on iPhone SE and iOS 26 simulator

## 3. Data Model and Export for Blade Editing

- [x] 3.1 Add `Take.bladeCuts: [Double]?` (sorted seconds, optional) persisted via SwiftData; derive `segments` from `duration` + `trimRange` + `bladeCuts`; lightweight migration keeps existing takes as single-segment (`nil`)
- [x] 3.2 Update `ExportService`/`AVMutableComposition` path: when `bladeCuts` is empty keep passthrough/single-filter; when non-empty build composition inserting each surviving segment, attach `AVVideoComposition` with `CIFilter.colorCube` only if `lutPreset != .natural` (otherwise passthrough); add unit tests for composition timeRanges
- [x] 3.3 Make `VideoPlayer` preview in Review honor blade composition (same composition builder as export) and add helper `bladeCuts` clamp/prune logic (0.1s minDistance, dedupe, trim-range pruning)

## 4. Blade Timeline UI in My Takes / Review

- [x] 4.1 Extend `TrimScrubberView` to render vertical cut dividers, segment selection highlight, playhead, and blade (scissors) button; Blade disabled when playhead at ends, Delete Segment disabled when single segment or no selection
- [x] 4.2 Wire My Takes `TrimScrubberView` blade action: on tap insert cut at playhead `CMTime.seconds`, sort/dedupe, persist `Take.bladeCuts`, update `duration`; segment tap selects, Delete Selected Segment compacts cuts, support Undo via `@State` snapshot stack for the Review session
- [x] 4.3 Ensure `onChange(trimRange)` prunes out-of-range cuts and that blade UI reflects pruned state; add empty-state/edge handling for zero-duration guard

## 5. Grouped Edit Menus

- [x] 5.1 Replace scattered swipe/toolbar actions in `MyTakesView` with grouped `Menu` sections: "Adjust" (Trim, Blade/Split at Playhead, Delete Selected Segment), "Color" (LUT submenu with swatches), "Output" (Save to Photos, ShareLink) — replicate consistently in row swipe trailing menu, context menu, and toolbar
- [x] 5.2 Apply the same grouped menu structure to `ReviewView` toolbar ellipsis (`Menu` with three Sections and matching disabled-state logic) and verify Save disabled while exporting, Blade/Delete states in sync with `MyTakesView`

## 6. Validation and Cleanup

- [x] 6.1 Add SwiftData lightweight migration test: existing takes without `bladeCuts` load as single segment; new takes round-trip blade edits
- [x] 6.2 Run `xcodebuild` + simulator smoke test on iPhone SE/mini (4-tab overflow), iPhone 15 Pro, and iPad; verify tab selection persistence, LUT swatch cache, blade split/delete/undo, and grouped menus across `MyTakesView` and `ReviewView`
- [x] 6.3 Remove dead code (`showStudio` overlay state, `StudioCover` where fully superseded, old text-only LUT rows) and run `swiftlint` / `swiftformat` with no new warnings
