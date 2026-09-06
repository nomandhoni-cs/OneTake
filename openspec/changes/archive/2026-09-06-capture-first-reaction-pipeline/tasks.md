## 1. Export Job Core

- [x] 1.1 Create `ReactionExportJob` skeleton (inputs: raw URL, BG media, style snapshot, audio settings; outputs: progress callback, cancel(), completion with temp URL or error) (inputs: raw URL, BG media, style snapshot, audio settings; outputs: progress callback, cancel(), completion with temp URL or error)
- [x] 1.2 Implement video path: camera `AVAssetReader` → `VNSequenceRequestHandler` `.accurate` (format via `supportedOutputPixelFormats()`) → `ReactionCompositor` → `AVAssetWriter` 1080p30 SDR: camera `AVAssetReader` → `VNSequenceRequestHandler` `.accurate` (format via `supportedOutputPixelFormats()`) → `ReactionCompositor` → `AVAssetWriter` 1080p30 SDR
- [x] 1.3 Add fps probe (first 30 frames) with auto-downgrade to `.balanced` + result note
- [x] 1.4 Implement BG timeline: video via `AVAssetReader` with loop/trim to camera duration; photo via static frame

## 2. Offline Audio

- [x] 2.1 Implement mic-envelope lookahead (~1 s) driving `ReactionDucking`, mixed via `mixSample`, AAC 44.1 kHz mono (mic-only for photo BG, mute honored)
- [x] 2.2 Verify sample-accurate mic/BG alignment by presentation timestamps on a synthetic fixture

## 3. Capture Simplification

- [x] 3.1 Slim `ReactionCaptureService` to compose `CaptureService` movie-file capture + independent BG playback; lock BG transport during recording with caption
- [x] 3.2 Replace live cutout preview with unmasked presenter-rectangle framing preview (geometry stays live)
- [x] 3.3 Delete `ReactionCaptureEngine.swift` (+ `MicConverter`) and dead realtime wiring; confirm no dangling references

## 4. Processing UI + Wiring

- [x] 4.1 Build `ProcessingView` (progress bar, cancel) and Stop → process → `Take(isReaction: true)` flow with atomic move + raw cleanup
- [x] 4.2 Implement failure path (raw kept, Retry/Discard), free-space precheck alert, and background-task assertion
- [x] 4.3 Add headphone suggestion caption for speaker bleed (accepted v1 limitation)

## 5. Tests

- [x] 5.1 Add `ReactionExportJobTests`: progress monotonicity, cancel deletes temp, BG loop/trim mapping, lookahead ducking on synthetic buffers
- [x] 5.2 Keep full suite green (compositor/ducking/chunker/model tests unaffected; update/remove realtime-only assertions)

## 6. Gates + Device QA

- [x] 6.1 Run `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test` (unit + reaction UI test)
- [x] 6.2 Update `docs/ARCHITECTURE.md`, `docs/CODEMAP.md`, `AGENTS.md` (pipeline section, deleted files, counts)
- [ ] 6.3 Device QA checklist: measure `.accurate` fps on A15/A17, export-time budget (target ≤1× duration for ≤3 min takes), thermal behavior, BLEED check on speaker-recorded take
