## Why

The Review editor is where takes become shareable, but three gaps hurt it: the "Save as New Take" button wraps to two lines on narrow screens, blade editing promises multi-chunk splits yet the timeline framing (segment identity, dividers, playhead) undersells it, and the 4-preset LUT shelf looks thin next to competitors. Fixing all three in one pass makes the editor feel finished — and a documented monetization plan (review-only, no paywall code yet) decides what stays free before we build it.

## What Changes

- Review actions row: single-line buttons at every width (`.lineLimit(1)` + scale-down instead of wrap); no behavior change to Save/Replace/Photos/Share.
- Blade timeline: repeated splits into N chunks stay first-class; ANY segment (first/middle/last, never the sole survivor) is selectable and deletable with compaction; timeline framing shows per-segment index + duration chips, cut dividers, selected outline, and playhead without label collisions.
- Blade correctness fix (the delete path is currently broken — verified by trace: deleting [5-12s] rewrites cuts to [5], whose derived segments [0-5]+[5-20] still contain the "deleted" footage, and export bakes it back in): takes gain an additive `segments: [BladeSegment]?` store of explicit source ranges; split/delete operate on ranges (trivially correct), `bladeSegments()` prefers stored ranges with legacy cut-derivation fallback, `bladeCuts` stays synced as internal boundaries, undo snapshots ranges.
- LUT collection grows 4 → 10 presets (6 new parametric grades); `LUTCubeLoader` + thumbnail renderer become size-aware (parse `LUT_3D_SIZE`, support 16/32/64) so new 32³ cubes ship small; picker, caching, missing-file fallback, and export paths unchanged.
- Pricing plan is DELIVERED AS A REVIEWABLE PLAN ONLY (`design.md` section → transcribed to `docs/PRICING.md` at apply time). No StoreKit code, no paywall UI, no entitlement checks in this change.

## Capabilities

### New Capabilities

- None (product surface unchanged; pricing is docs-only by explicit request).

### Modified Capabilities

- `blade-timeline-editing`: segment deletion expands from interior-only to any segment; adds timeline framing requirements (chips/dividers/playhead); repeated-split flow clarified.
- `trim-color-export`: actions-row single-line layout requirement; LUT requirement expands from 4 fixed 64³ presets to a 10-preset size-aware collection.

## Impact

- Affected code: `Features/Review/` (`ReviewView` actions row + split/delete/undo, `TrimScrubberView` framing), `Core/Persistence/Script.swift` (`BladeSegment` + `Take.segments`, additive Optional → lightweight migration per `docs/PERSISTENCE.md` §4, no version bump), `Core/LUTs/` (size-aware loader + thumbnails), `LUTPreset` +6 cases, `Resources/*.cube` (+6 files ≈ 3 MB at SIZE 32), `OneTakeTests` (LUT + blade UI + engine regression tests), `docs/PRICING.md` (new, docs-only).
- Dependencies: none new — SwiftUI layout, `CIFilter.colorCube` (already size-parametric), StoreKit explicitly NOT touched.
- Risks: `.cube` subjective quality needs on-device visual QA (mitigated by swatch renders + small size for cheap iteration); bundle grows ~3 MB (mitigated by SIZE 32 instead of 64).
