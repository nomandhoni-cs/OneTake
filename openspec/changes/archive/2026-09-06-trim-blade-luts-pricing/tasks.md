## 1. Actions Row Layout

- [x] 1.1 Add `.lineLimit(1)` + `.minimumScaleFactor(0.85)` to Save/Replace labels (Review is unreachable in sim UI tests without camera hardware — verified via layout reasoning + canvas Preview)

## 2. Blade Engine Correctness

- [x] 2.1 Add `BladeSegment` (`Codable`, start + duration) + additive `Take.segments: [BladeSegment]?`; repoint `bladeSegments()` to stored ranges with legacy cut-derivation fallback
- [x] 2.2 Rewrite split/delete/trim-clip/undo onto stored ranges with `syncCutsFromSegments()` invariant (cuts stay as divider positions)
- [x] 2.3 Add regression tests: delete-middle excludes the interval from `bladeSegments()` and effective duration; delete-first/last edge cases; legacy derive-on-first-edit; undo restores ranges

## 3. Blade Timeline Framing

- [x] 3.1 Add per-segment duration tags, selected `Segment i/N • m:ss` readout, divider/playhead clamping in `TrimScrubberView`
- [x] 3.2 Wire multi-split flow + delete-any-segment affordance with sole-survivor guard; cover split→split→delete→undo in unit tests (Review UI unreachable in sim)

## 4. LUT Collection Expansion

- [x] 4.1 Make `LUTCubeLoader` + thumbnail renderer size-aware (sniff Adobe text vs legacy raw binary; 16/32/64); unit test parsing incl. legacy 4 MB files byte-identical
- [x] 4.2 Add `tools/generate_luts.py` emitting the 6 graded SIZE-32 cubes; review swatch renders
- [x] 4.3 Add 6 `LUTPreset` cases + `.cube` resources; verify picker lists 10 with swatches, missing-file fallback intact
- [ ] 4.4 On-device visual QA of all 10 grades (taste gate incl. gradient banding check) — BLOCKED: no physical device; sim parse/direction/swatch tests green

## 5. Pricing Plan Doc (docs-only, no paywall code)

- [x] 5.1 Transcribe the approved §5 pricing plan verbatim into `docs/PRICING.md` and link it from `README.md` + `AGENTS.md`

## 6. Gates

- [x] 6.1 Run `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test` (full unit suite + studio/onboarding UI tests)
- [x] 6.2 Update `docs/ARCHITECTURE.md`, `docs/CODEMAP.md`, `AGENTS.md` (blade model, LUT shelf, counts)
