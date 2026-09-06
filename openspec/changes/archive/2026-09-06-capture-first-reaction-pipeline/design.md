## Context

`reaction-studio-cutout` (implemented, 18/18, unarchived) records reactions in
real time: every camera frame goes through Vision `.balanced` segmentation,
CoreImage compositing, and `AVAssetWriter` encoding on a reference clock, while
mic/BG audio is mixed per-chunk with causal ducking (`ReactionCaptureEngine`,
~500 lines plus `MicConverter`/`PCMChunker` sync machinery). It works, and 54
tests pass — but ANE + GPU + encoder run simultaneously for the whole take, any
hitch ruins the recording irreversibly, and quality is capped at `.balanced`
with stale-mask holds under load.

The question: capture plain footage first, process after Stop — and do the
Vision APIs (`qualityLevel`, `VNSequenceRequestHandler`, output pixel formats)
actually help? This design compares both options on evidence and picks one.

## Goals / Non-Goals

**Goals:**

- Decide realtime vs capture-first with explicit trade-offs, then specify the winner.
- Higher cutout quality, teleprompter-grade capture reliability, retryable failures.
- Net code deletion: reuse `ReactionCompositor`, `PersonSegmenter`,
  `ReactionDucking`/`PCMChunker`, `BackgroundSource`; retire the realtime engine.
- Keep every spec promise that isn't about *when* processing happens (layouts,
  outline, ducking behavior, Take integration, optional script overlay).

**Non-Goals:**

- Keeping both pipelines (no realtime + export dual mode in v1).
- Live WYSIWYG cutout preview — accepted loss, replaced by honest framing preview.
- Headphone/BLE monitoring modes, multi-person instance masks, HDR composites.

## Decisions

### 1. Verdict: capture-first wins — comparison

| Dimension | A. Realtime (current) | B. Capture-first + post-process |
|---|---|---|
| Segmentation quality | `.balanced` only; mask-hold reuses stale masks under load | `.accurate` + `VNSequenceRequestHandler` temporal consistency |
| Failure blast radius | ANE/GPU/encode hitch ruins the take irreversibly | Capture is the proven movie-file path; export failure keeps raw file + retry |
| Thermal / battery | Sustained triple load for the whole recording | Light capture; heavy work bounded in one export job |
| Pause | Custom clock-continuity machinery | Free via movie-file pause (teleprompter semantics) |
| A/V sync | Custom chunk alignment (±120 ms tolerance, drift-prone) | Offline sample-accurate alignment by presentation timestamps |
| Ducking | Causal only — no lookahead, reactive release | ~1 s envelope lookahead — smoother, no pumping |
| Time-to-file | Instant at Stop | Export wait (~0.5–2× take length; device benchmark in tasks) |
| Disk | 1× (final only) | Transient ~2× (raw + final), temp cleaned after success |
| Preview | True WYSIWYG cutout | Framing preview (unmasked presenter rect over BG) |
| Code | ~500-line engine + converter/chunker/sync | Job reuses 4 existing types; engine deleted |

Reliability dominates in a one-take app: a ruined recording cannot be redone,
while a progress-visible wait can. **Decision: Option B.** The export wait is
the honest cost, mitigated by progress + cancel + background-task assertion.

### 2. Yes, the pasted Vision APIs directly enable the win

- `qualityLevel .accurate`: only viable offline — too slow/jittery for a 30 fps
  realtime guarantee, especially on A14/A15. Post-capture it just costs time.
- `VNSequenceRequestHandler`: built for frame sequences; as a stateful request,
  person segmentation gets temporal consistency (less edge flicker) versus the
  per-frame `VNImageRequestHandler` the realtime path uses.
- `supportedOutputPixelFormats()`: pick the optimal mask format at runtime
  instead of hardcoding `OneComponent8`.
- `VNGeneratePersonInstanceMaskRequest`: explicitly NOT used — single presenter,
  heavier, no benefit. (Answers "will this help": no.)

### 3. Capture becomes boring on purpose

`ReactionCaptureService` composes a plain `CaptureService` (movie file, front
camera + mic, exposure lock, pause/resume segments, backgrounding finalize)
instead of owning data outputs. `BackgroundSource` keeps playing the BG for the
performer to react to. No inference, no writer, no mixer runs during capture —
the recording path is then identical in risk to the shipped Teleprompter path.

### 4. BG transport is locked during recording — sync becomes trivial

Realtime needed a reference clock because BG and camera ran on different
timelines. Capture-first constrains instead: Restart/replace BG is
preview-only; during recording the BG plays linearly and pauses with the take.
Mapping is then `bgTime = cameraTime − pausedTotal` — no clock sync code, and
the export aligns BG samples by exact timestamps. (Mic will pick up some BG
speaker bleed; accepted v1 limitation with a headphone suggestion caption —
same character as filming a TV.)

### 5. `ReactionExportJob`: reader → segment → composite → writer, offline

New job type (background queue, cancellable, progress-reporting):

1. `AVAssetReader` on the raw camera file (video BGRA + audio float-mono
   44.1 kHz) and on the BG asset's audio track (video BG only).
2. Per video frame: `VNSequenceRequestHandler.perform([segmentRequest])` at
   `.accurate` → mask → existing `ReactionCompositor.composite` with the
   frozen `ReactionStyle` snapshot → `AVAssetWriter` 1080p30 SDR (H.264).
   BG frames come from an `AVAssetReader` too (deterministic, no player
   clock): loop the BG if shorter than the take, stop at camera end if longer;
   photo BG renders the static image every frame. First-30-frames fps probe
   auto-downgrades to `.balanced` with a note if `.accurate` is too slow.
3. Audio: single pass with ~1 s mic-envelope lookahead feeding the existing
   `ReactionDucking` curve, mixed with `ReactionAudioMixer.mixSample`, AAC.
4. Progress = processed / total frames; cancel stops readers/writer and deletes
   temp; success atomically moves temp into `Takes/` and deletes the raw file.

### 6. Processing UI + temp lifecycle

Stop → `ProcessingView` (progress bar, cancel) → success saves
`Take(isReaction: true)` and returns to picker/MyTakes; failure keeps the raw
camera file and offers Retry (re-run job) / Discard (delete raw). Free-space
precheck before export (needs ~2× take size); `beginBackgroundTask` so
backgrounding doesn't kill the job — if the OS still kills it, the raw file
persists and retry is offered on return.

## Risks / Trade-offs

- [Risk] Export wait annoys on long takes → Mitigation: progress + cancel,
  fps-probe downgrade, device benchmark task sets the documented budget
  (target ≤1× duration for ≤3 min takes on A15+).
- [Risk] 2× transient disk on nearly-full phones → Mitigation: precheck with
  explanatory alert; raw deleted immediately after success.
- [Risk] `.accurate` still too slow on A14 → Mitigation: auto-downgrade to
  `.balanced` (equals today's quality, still with retry + better audio).
- [Risk] Speaker bleed in mic track → Mitigation: accepted v1 limitation,
  headphone caption; clean BG track still mixed at ducked level.
- [Trade-off] No live cutout preview → accepted; framing preview shows exact
  placement/geometry, cutout visible seconds later after export.
- [Trade-off] Instant file lost → accepted per reliability argument above.

## Migration Plan

1. Add `ReactionExportJob` + processing UI alongside the current pipeline
   (no behavior change yet; job covered by tests on synthetic assets).
2. Switch `ReactionStudioView` Stop flow to capture-file → process → Take.
3. Slim `ReactionCaptureService` to capture orchestration; simplify preview.
4. Delete `ReactionCaptureEngine.swift` (+ `MicConverter`); update docs/tests.
5. Rollback before archive: revert the Stop-flow switch commit; engine file
   restored from git. After archive, rollback is a new change.

## Open Questions

- Measured `.accurate` fps on A15 vs A17 (device QA task) — sets the budget.
- Keep-raw-file option in settings for creators who want to re-export? Default:
  no (storage simplicity); revisit if retry data demands it.
- Export time estimator shown before Stop on takes >5 min? Default: no, keep UI calm.
