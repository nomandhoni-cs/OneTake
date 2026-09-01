## Why

The bottom navigation currently shows a 3-tab pill (My Takes / Scripts / Profile) with Studio as a detached floating circle outside the pill. This breaks the expected iOS tab-bar model, hides Studio from the switcher, and forces a modal presentation. Separately, LUT selection shows only text names with no visual preview, so users cannot judge the grade before export. Finally, My Takes has no segment-level editing — users can only trim ends, not split (blade) and delete interior portions, and the edit menu scatters Trim/LUT/Share actions without grouping.

## What Changes

- **BREAKING**: Move Studio from `overlay` floating circle + `fullScreenCover` into the native `TabView` as the 4th tab (`value: .studio`, title "Studio", `video.fill` / `video` SF Symbols). Remove `showStudio` overlay button and `StudioCover` presentation; Studio now participates in tab state, per-tab `NavigationPath`, and `@SceneStorage` selection. Deep link `showStudio` notification routes to `selectedTab = .studio`.
- Add **unified 4-tab pill/TabView**: `[My Takes] [Scripts] [Studio] [Profile]` sharing the same `TabView`/`sidebarAdaptable` Liquid Glass container — no second capsule, no external HStack. Icon + label, 44pt hit target, VoiceOver order My Takes → Scripts → Studio → Profile.
- Fix **LUT preview**: Replace text-only `Picker` rows with preview swatches. Each `LUTPreset` row shows a 40×24 gradient swatch rendered from its `.cube` file via `CIImage` → `CGImage` thumbnail (or on-device still thumbnail tinted by the LUT's dominant transform) plus display name. Natural shows neutral gray; Warm Studio / Cinematic Contrast / Clean Monochrome show their characteristic tint. Cached thumbnails, regenerated on LUT file change.
- Implement **blade timeline editing in My Takes / Review**: Add playhead-positioned blade (scissors) tool on the trim timeline to split a `Take` into two segments at `CMTime`. Segments become independently trimmable; selected segment can be deleted. Deletion compacts timeline, updates `Take` duration, and offers Undo. Underlying model: `Take` gains `segments: [Segment]` or `bladeCuts: [CMTime]` persisted via SwiftData; export composes segments with `AVMutableComposition` / `AVVideoComposition` (passthrough when no LUT, `CIFilter.colorCube` when graded).
- **Group edit-menu actions in My Takes**: Replace scattered swipe/toolbar buttons with a grouped edit menu: Section "Adjust" → Trim, Blade/Split, Delete Segment; Section "Color" → LUT (with preview swatch); Section "Output" → Save to Photos, Share. Consistent placement in swipe trailing menu, context menu, and Review toolbar ellipsis.

## Capabilities

### New Capabilities
- `unified-tab-navigation`: 4-tab `TabView` shell where Studio is a first-class tab inside the switcher (My Takes / Scripts / Studio / Profile), with shared Liquid Glass styling, per-tab navigation stacks, selection persistence, and deep-link routing.
- `blade-timeline-editing`: Blade/split tool on the footage timeline to cut at playhead, manage resulting segments, delete interior portions, compact the timeline, and undo — integrated with trim and export composition.

### Modified Capabilities
- `trim-color-export`: Add rendered LUT preview swatches to the LUT picker and group Trim / Blade / LUT / Export actions into consistent menu sections; extend export to compose blade segments.

## Impact

- **Code**: `RootTabView.swift` (AppTab + TabView, remove overlay/`StudioCover`/`showStudio` fullScreenCover, add studio tab + path), `MyTakesView.swift` (blade UI, segmented timeline, delete-segment, grouped menus), `ReviewView.swift` / `TrimScrubberView.swift` (LUT swatch cells, grouped toolbar, blade overlay), `Core/Persistence` (Take segments model, migration), `Core/Export` (composition export), `Assets/Resources` LUT thumbnails cache.
- **UX**: Studio discoverable as a tab; LUT choice becomes visual; My Takes gains non-destructive segment editing with grouped, HIG-consistent menus.
- **Data**: Lightweight SwiftData migration adding segment storage to `Take`; existing takes migrate as single-segment.
- **Risks**: 4 tabs near iOS tab-bar limit but within HIG (≤5); blade AVComposition must stay <1s for passthrough and handle LUT + multi-segment in one pass.
