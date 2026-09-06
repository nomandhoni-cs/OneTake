## Why

The Reaction Studio built in `reaction-studio-cutout` composites, segments, and encodes simultaneously on-device: any ANE/GPU hitch during recording permanently degrades the take, and the pipeline is locked to `.balanced` segmentation with causal (lookahead-free) ducking. Capturing plain camera footage first and processing after Stop trades a short, progress-visible export wait for higher quality, a proven capture path, and a retryable job — strictly better reliability for a one-take app where a ruined recording cannot be redone.

## What Changes

- Reaction recording captures front camera + mic with the standard `AVCaptureMovieFileOutput` path (same battle-tested semantics as Teleprompter: pause/resume, backgrounding finalize) while the BG media plays independently; no live segmentation, no live `AVAssetWriter`, no sample-level audio mixing during capture.
- New post-capture export job runs after Stop: per-frame person segmentation at `.accurate` quality through `VNSequenceRequestHandler` (temporal consistency), the existing `ReactionCompositor` for blending, and offline mic/BG audio mixing with lookahead ducking — producing the same single composited MP4 `Take(isReaction: true)`.
- New processing UI: progress bar with cancel; failure keeps the raw camera file and offers retry instead of losing the take.
- Live preview shows the camera as an unmasked presenter rectangle over the BG (honest framing preview, zero inference cost); cutout/layout/outline choices still apply at export and are previewed as geometry.
- **BREAKING (internal):** retires `ReactionCaptureEngine` (realtime writer + chunk-mixer, ~500 lines) and the realtime segmentation submit path; `ReactionCompositor`, `PersonSegmenter`, `ReactionDucking`/`PCMChunker`, and `BackgroundSource` are reused by the export job.

## Capabilities

### New Capabilities

- `reaction-post-processing`: Post-capture export job — `.accurate` sequence segmentation, WYSIWYG composite render, offline lookahead-ducked audio mix, progress/cancel/retry, temp-file lifecycle.

### Modified Capabilities

- `capture-engine`: Reaction capture uses the standard movie-file path (front camera + mic, teleprompter pause/backgrounding semantics) with the BG playing independently; the composited-writer recording path is removed.

## Impact

- Affected code: `Features/Studio/Reaction/` — new `ReactionExportJob` + processing UI; `ReactionCaptureService` slimmed to capture orchestration; `ReactionCaptureEngine.swift` deleted; `ReactionStudioView` transport/preview updated; `StudioSettingsSheet` unchanged.
- Dependencies: none new — Vision (`VNSequenceRequestHandler`, `.accurate`), CoreImage, AVFoundation (`AVAssetReader`/`AVAssetWriter`), all first-party and offline.
- Risks: export wait scales with take length (mitigated by progress + cancel + background-task assertion; device benchmark in tasks); transient 2× disk usage during export (mitigated by temp cleanup + free-space precheck).
- Builds on unarchived `reaction-studio-cutout` (18/18 implemented): reuses its specs for layouts, audio behavior, and Take integration; supersedes only its realtime pipeline decision.
