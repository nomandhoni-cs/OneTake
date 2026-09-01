## Context

OneTake currently uses a hybrid navigation shell: `RootTabView` hosts a native `TabView(sidebarAdaptable)` with three tabs (My Takes / Scripts / Profile) rendered as a Liquid Glass pill, plus a detached trailing floating circle for Studio (`video.fill`, 56pt, `glassEffect`/`Circle.fill(accent)`). Studio is presented via `fullScreenCover` from `showStudio` state and `showStudio` notification (`onReceive`). Per-tab `NavigationPath`s (`takesPath`, `scriptsPath`, `profilePath`) are held in `RootTabView` but Studio has no path — it is ephemeral.

The LUT picker in `ReviewView` is a `ForEach(LUTPreset.allCases) { Text(displayName) }` with no visual preview. `LUTCubeLoader` and `LUTPreset.cubeData` exist and `.cube` files live in `Resources/`, but the UI never renders them. `TrimScrubberView` exposes a dual-handle scrubber for start/end trim only (`trimRange: CMTimeRange`). Export via `ExportService` uses `AVAssetExportSession` passthrough or `CIFilter.colorCube` single-pass.

My Takes (`MyTakesView`) lists takes grouped by day with search over `scriptTitle` and badges for trim/LUT, and swipe actions for Delete/Edit. Actions are scattered across swipe trailing/leading and toolbar, with no section grouping.

Constraints: Deployment `IPHONEOS_DEPLOYMENT_TARGET = 18.6` (project 26.5), SwiftData, SwiftUI + Observation, no third-party deps, HIG tab limit ≤5 on iPhone, Liquid Glass available on iOS 26.

## Goals / Non-Goals

**Goals:**
- Studio becomes a first-class 4th tab inside the same `TabView` pill/switcher with shared selection persistence, VoiceOver order, and deep-link routing — eliminating the external `HStack` overlay and `fullScreenCover` path.
- LUT selection shows a rendered color swatch per preset so the grade is legible before export, with caching and correct Natural identity.
- Blade editing on the My Takes timeline: split at playhead into segments, select/delete interior segments, compact the timeline, undo, and export the composed result correctly with or without a LUT.
- Edit actions (Trim, Blade/Split, Delete Segment, LUT, Save, Share) grouped consistently in `Menu` sections ("Adjust" / "Color" / "Output") across swipe menu, context menu, and Review toolbar.

**Non-Goals:**
- Full NLE features (transitions, audio ducking, keyframes, multi-track).
- Waveform/zoomable timeline with audio lane.
- Cloud sync or collaborative editing.
- Custom LUT import; only the four bundled `.cube` presets.

## Decisions

**Decision: 4-tab native TabView, drop custom pill + overlay.**
- What: Extend `AppTab` to `takes, scripts, studio, profile`; add `Tab("Studio", systemImage: "video.fill", value: .studio) { StudioTab(path: $studioPath) }`; remove `overlay` HStack, `BottomPillBar`, `StudioCover`, and the `showStudio` fullScreenCover path; keep single `TabView` with `sidebarAdaptable` so Liquid Glass is provided by the system.
- Why: User explicitly asked for Studio inside the switcher; native TabView gives correct HIG focus order, large hit targets, and selection persistence for free vs maintaining a bespoke pill + external button that duplicates capsules on iOS 26. Alternative — adding a 4th item to the custom pill — was rejected because it would retain custom layout, manual accessibility, and the modal lifecycle that the request seeks to remove.
- Trade: Less pixel control over the pill's capsule metrics, but aligns with HIG and simplifies state.

**Decision: Studio tab lifecycle tied to tab visibility, not a sheet.**
- What: Hold `@State private var studioPath = NavigationPath()` in `RootTabView`; Studio's `CaptureService.session` starts on `onAppear` when `selectedTab == .studio` and stops on `onDisappear`/`scenePhase background`. `showStudio` notification now sets `selectedTab = .studio` and optionally pushes `StudioView` with `initialScriptID` via `studioPath`.
- Why: Keeps AV session alive only while the tab is visible, avoids a second navigation stack inside a sheet, and preserves per-tab back stacks. Alternative — keep a hidden sheet presented from the tab — was rejected because it reintroduces two layers and complicates deep links.
- Trade: Switching away from Studio mid-recording must confirm discard/pause; implement `onChange(selectedTab)` guard with `confirmationDialog`.

**Decision: LUT swatches rendered on-device via CoreImage, cached.**
- What: For each `LUTPreset`, generate a 40×24 `CGImage` thumbnail by applying `CIFilter.colorCube(cubeDimension: 64, cubeData:)` to a neutral gradient `CIImage` via `CIContext(mtlDevice:)`; cache in `NSCache<NSString, CGImage>` keyed by `rawValue` + `cubeData` hash, invalidated when `.cube` file mtime changes. Natural returns a neutral gray swatch without a filter pass. Thumbnail creation is async (`Task.detached`) and falls back to a tinted placeholder if `cubeData` is nil.
- Why: Shows the actual transform of the shipped `.cube` files, not a hand-authored asset that can drift. Pre-rendered PNG assets would need manual updates per LUT tweak.
- Alternative — bundling static PNG swatches — rejected for drift and extra asset maintenance.
- Trade: First render costs a CI pass (~5–10ms on A17), hence the cache; no disk persistence needed.

**Decision: Blade model as lightweight cuts array on Take, not a new @Model.**
- What: Add to `Take`: `@Attribute var bladeCuts: [Double]?` (seconds, sorted, persisted as JSON-transformable via SwiftData's `ValueTransformer` or raw `Data` with `Codable` helpers). Effective segments are derived as `derivedSegments(from: duration, cuts: bladeCuts, trimRange)`. Deleting a segment removes its interval and compacts subsequent cuts. Undo via `UndoManager` / local `@State` stack of `bladeCuts` snapshots for the current edit session.
- Why: Adding an optional property is a trivial lightweight SwiftData migration vs introducing `Segment @Model` with relationships and an extra table for what is effectively an ordered double array. Keeps export composition simple and matches the existing `Take` pattern (`trimStartSeconds`/`trimDurationSeconds` stored as `Double?`).
- Alternative — `Segment` entity with `start/duration/isDeleted` and `@Relationship` — rejected for schema weight for a pre-1.0 app.
- Trade: Must keep cuts sorted and clamped to `(trimStart, trimEnd)` and deduplicate on split.

**Decision: Export composition via AVMutableComposition + AVVideoComposition.**
- What: When `bladeCuts` is empty, keep current passthrough / single-filter path. When non-empty, build `AVMutableComposition` inserting each surviving segment's `timeRange` from the source `AVAsset`, then attach an `AVVideoComposition` with `CIFilter.colorCube` applied via `applyingCIFiltersWithHandler` only when `lutPreset != .natural`. Passthrough preset is used when no LUT, otherwise highestQuality.
- Why: Reuses the existing `ExportService`/`ExportService2` pipeline; composition approach handles trimmed + split + graded in one pass. Alternative — sequential `AVAssetExportSession` chaining — was rejected for quality loss and temp-file proliferation.
- Trade: Composition export cannot be passthrough when LUT is active; must re-encode. Keep <1s target for ≤30s clips via Metal.

**Decision: Grouped menus via Menu + Section.**
- What: In `MyTakesView` row swipe/context menu and `ReviewView` toolbar `Menu`, create three `Section`s: "Adjust" (Trim, Blade/Split at Playhead, Delete Selected Segment), "Color" (LUT submenu with swatches), "Output" (Save to Photos, ShareLink). Disabled states: Blade disabled when playhead at ends, Delete disabled when no selection or single-segment, Save disabled while exporting.
- Why: HIG recommends sectioned menus for distinct action families; prior scattered buttons violated proximity and scanability. Alternative — segmented picker — rejected for taking vertical space.

## Risks / Trade-offs

- [Risk] 4 tabs crowd the bar on SE/mini → Mitigation: use short titles ("Takes" vs "My Takes" on compact), rely on `sidebarAdaptable` overflow; keep Studio icon `video` (inactive) / `video.fill` (active) for legibility.
- [Risk] Moving Studio from modal to tab breaks existing `showStudio` fullScreenCover call sites (e.g., `ContentView`, editor "Record with Prompter") → Mitigation: keep `Notification.Name.showStudio` but handler sets `selectedTab = .studio` and pushes via `studioPath`; add deprecation shim if needed.
- [Risk] Blade cuts at exact asset boundaries cause zero-duration segments → Mitigation: clamp cuts `minDistance 0.1s` from neighbors and trim handles; ignore cuts within `trimRange` epsilon.
- [Risk] SwiftData migration for `bladeCuts` on existing takes → Mitigation: optional `[Double]?` defaults to `nil` (single-segment); lightweight auto-migration; existing takes migrate as-is.
- [Risk] LUT thumbnail CI work on main thread → Mitigation: generate off-main, cache, show placeholder until ready; `CIContext` created once.

## Migration Plan

1. Add `bladeCuts: [Double]?` to `Take` (optional, default nil) + helper `derivedSegments`; Schema version bump handled by lightweight migration — no manual mapping.
2. Land `RootTabView` 4-tab change behind no flag (BREAKING navigation) — single PR; deep-link notification rerouted.
3. Land LUT swatches (add `LUTCubeThumbnailProvider`); no data migration.
4. Land blade UI + composition export; feature flag `bladeEditingEnabled` (internal `UserDefaults` "bladeEnabled" default true) allows quick rollback to trim-only by hiding blade entry and skipping composition branch.
5. Rollback: revert tab change by restoring overlay + fullScreenCover; revert blade by ignoring `bladeCuts` (takes play as single segment). No store downgrade needed because `bladeCuts` is optional.
6. Archive this change updates `specs/app-navigation`? Actually `unified-tab-navigation`, `blade-timeline-editing`, and `trim-color-export` deltas.

## Open Questions

- Should the Studio tab embed the camera full-bleed (edge-to-edge) or inset with standard safe areas? Proposal: full-bleed with `ignoresSafeArea` for preview, chrome in safe areas — to confirm with HIG review build.
- Should deleting a segment be destructive or move to a "Trash" holding segment for the session? Proposal: immediate delete + Undo snackbar (like Photos), not a persistent trash.
- LUT swatch source: neutral gradient vs actual video frame thumbnail? Proposal starts with gradient for determinism; follow-up could sample the take's middle frame for a content-aware preview.
