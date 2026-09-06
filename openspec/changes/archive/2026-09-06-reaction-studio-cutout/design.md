## Context

OneTake's Studio today is a single-mode teleprompter camera: `StudioView` owns an `AVCaptureSession` (front camera via `CaptureService`), a lens-anchored `PrompterView`, and a settings sheet, presented inline as a first-class tab (`RootTabView` → `StudioTab`). Takes are recorded with `AVCaptureMovieFileOutput` and flow into My Takes for blade/trim/LUT/export.

The Reaction Studio change adds a second capture mode to the same tab. It introduces a real-time compositing pipeline that does not exist in the codebase: front-camera frames + Vision person mask + background media frames blended on the GPU and encoded with `AVAssetWriter`. It also changes Studio-tab navigation (picker → full-screen mode) and reuses the script selector/prompter as an optional overlay.

Constraints: 100% SwiftUI + SwiftData, no third-party deps, offline-first, iOS 18.6+, must keep `swiftlint` at 0 violations and existing 33 tests green. All Apple frameworks involved (Vision, CoreImage/Metal, AVFoundation, PhotosUI) are first-party and available on the deployment target except where noted.

## Goals / Non-Goals

**Goals:**

- Studio tab offers two modes (Teleprompter / Reaction) via a 2-card picker; each mode opens full-screen with the tab bar hidden and dismisses back to the picker.
- Reaction mode records a single composited MP4 `Take` (person cutout over BG video/image) that behaves like any other take downstream (blade, trim, LUT, export, Photos save).
- Cutout quality runs at 30fps minimum on A15+ via ANE segmentation + GPU compositing, with graceful degradation on older silicon.
- Mic + BG audio mix with voice ducking and dual meters; optional script overlay reusing existing prompter semantics (pause freezes scroll).

**Non-Goals:**

- Web-URL import and slide-deck (PDF/Keynote) backgrounds — v1 is Photos library video/image only.
- HDR in reaction composites (SDR fallback v1); multi-person selection (largest/closest person only).
- Live-streaming, collab, or cloud processing — strictly on-device and offline.
- Changing the teleprompter recording path — it keeps `AVCaptureMovieFileOutput` untouched.

## Decisions

### 1. Mode picker lives in `StudioTab`, modes present via `fullScreenCover`

`StudioTab` becomes a picker view (two cards: Teleprompter with `video.fill` + script glyph, Reaction with `person.crop.rectangle.stack`). Tapping a card sets an enum `StudioMode` and presents the corresponding view in `fullScreenCover`, which hides the `TabView` tab bar automatically. Dismiss returns to the picker; `Notification.Name.showStudio` deep-links select the tab and optionally pre-select a mode/script.

Alternative considered: push modes on `studioPath` NavigationStack. Rejected — a pushed view keeps the tab bar visible, violating the requirement that recording be distraction-free full-screen; `fullScreenCover` is the idiomatic HIG full-camera pattern and preserves per-tab `NavigationPath` state untouched.

### 2. Separate `ReactionCaptureService` (@Observable) beside `CaptureService`, sharing helpers

Reaction recording uses `AVCaptureVideoDataOutput` + `AVCaptureAudioDataOutput` (per-frame access) instead of `AVCaptureMovieFileOutput`, so it gets its own service rather than branching `CaptureService`. Shared concerns are reused, not duplicated: `AudioSessionService` (session category), `ThermalMonitor` (throttle/degrade), `HapticsService`, `RecordingActivityService`, `ScriptSelectorView` logic, and `PrompterView` for the overlay.

Alternative considered: extend `CaptureService` with a reaction branch. Rejected — the output, encoding, audio-graph, and lifecycle semantics differ enough that branching would tangle the teleprompter path that 33 tests cover; a sibling service keeps blast radius zero.

### 3. Segmentation via `VNGeneratePersonSegmentationRequest` (.balanced), throttled to every frame at 30fps

Each camera frame is run through Vision's person-segmentation request on a dedicated background queue; the resulting single-channel mask (`CVPixelBuffer`) feeds the compositor. Quality level `.balanced` (not `.accurate`) keeps 30fps on A15+; if frame latency exceeds budget, the service skips segmentation for alternate frames and reuses the last mask (temporal hold) rather than dropping camera frames.

Alternative considered: CoreML custom portrait-matte model. Rejected — Vision's built-in request is ANE-accelerated, maintained by Apple, zero-asset, and designed exactly for this use case.

### 4. Compositing with CoreImage `CIBlendWithMask` on a shared `CIContext(.metal)`

A `ReactionCompositor` object holds a Metal-backed `CIContext` and per-frame composes: background frame (BG video via `AVPlayerItemVideoOutput` or static image) as input image, camera frame as foreground, Vision mask (scaled/aligned to camera frame) as mask. Layout modes are transforms applied before blending: full-silhouette (full-frame mask), circle-PiP (mask intersected with circle + positioned/scaled at presenter rect), split-screen (side-by-side, mask only on presenter half). Outline glow is a dilated-mask stroke (`CIMorphologyMaximum` + `CIBlendWithMask` tint) composited under the cutout. The same composited `CIImage` feeds both the `CAMetalLayer`/SwiftUI preview and the `AVAssetWriter` pixel-buffer input, guaranteeing WYSIWYG.

Alternative considered: Metal custom shaders or `AVVideoCompositionCoreAnimationTool`. Rejected — CoreImage gives GPU performance with far less code, and preview/encode share one code path, eliminating preview-vs-file divergence bugs.

### 5. Recording via `AVAssetWriter` (video + mic-audio + BG-audio mix), BG clock drives A/V sync

`AVAssetWriter` with `AVAssetWriterInputPixelBufferAdaptor` (H.264, 1080p30 v1) writes composited frames; two audio inputs (mic PCM from capture output, BG track via `AVAssetReader` on the BG asset or tap on the player) are mixed in a small `ReactionAudioMixer`: voice-activity detection on mic power lowers BG gain to 30% with ~150ms attack / ~800ms release. The BG `AVPlayer` clock is the presentation-time master — composited frame timestamps follow the BG item time so lip-sync drift cannot accumulate; camera frames are resampled to that clock.

Alternative considered: `AVCaptureMovieFileOutput` + post-process composition at Stop. Rejected — post-processing doubles wait time and memory for long reactions and denies live WYSIWYG preview; real-time encode is the standard pattern for reaction apps.

### 6. `Take` gains additive `isReaction` flag; BG reference stored, BG bytes not copied

`Take` gets optional `isReaction: Bool = false` plus `backgroundAssetLocalID: String?` (Photos local identifier for re-pick) — both optional with defaults so the SwiftData migration is lightweight/additive, matching the `bladeCuts` precedent. The composited MP4 is self-contained; the BG identifier is metadata only (badge in My Takes, "reaction" filter), never required for playback.

## Risks / Trade-offs

- [Risk] ANE + GPU + encode thermal load on long takes → Mitigation: reuse `ThermalMonitor`; on `serious` state auto-degrade (mask reuse every 2nd frame, then PiP-without-mask fallback) and show the existing thermal banner.
- [Risk] Older devices (A14 and below) cannot hold 30fps segmentation → Mitigation: capability check at mode entry; fallback offers circle-PiP with rectangular (unmasked) presenter + explanatory caption rather than blocking entry.
- [Risk] DRM/protected Photos videos fail `AVAssetReader`/export → Mitigation: detect `isPlayable`/`hasProtectedContent` at pick time; reject with an alert guiding the user to pick another clip.
- [Risk] `fullScreenCover` from a tab breaks `showStudio` deep-link while recording → Mitigation: `RootTabView` guards tab switches during recording with the existing leave-confirmation pattern (`showLeaveConfirm`); deep-link while reaction-recording shows the confirm sheet instead of yanking the session.
- [Risk] A/V drift between mic, BG, and composited clock → Mitigation: single master clock (BG item time), audio mixer timestamps from the same `CMClock`; QA scenario asserts <80ms sync on a 5-min reaction.
- [Trade-off] v1 SDR-only composites even when HDR is enabled → accepted; HDR toggle hidden in reaction settings with "SDR in Reaction v1" caption, teleprompter path unaffected.
- [Trade-off] Pause in reaction mode restarts BG from pause point (BG `AVPlayer` pause/resume + writer `markAsFinished`-segment merge) rather than true writer pause → accepted; matches existing studio-controls pause semantics (single merged MP4, no orphans).

## Migration Plan

1. Land additive `Take` fields (`isReaction`, `backgroundAssetLocalID`) with defaults — no data migration, old takes read as non-reaction.
2. Ship picker + teleprompter `fullScreenCover` first (navigation change only, camera path untouched), then reaction pipeline behind the same picker card.
3. Rollback is per-slice: picker reverts to direct camera tab; reaction service files are additive and delete-safe.
4. Update `docs/ARCHITECTURE.md` (§4 navigation, §6 Studio/export), `docs/CODEMAP.md` (new files), and `AGENTS.md` date line on landing.

## Open Questions

- Minimum bar: ship 1080p30 reaction encode only, or also 720p fallback for A14? (Default: 1080p30 + auto-degrade; revisit after device testing.)
- Should circle-PiP position/scale persist per user (`@AppStorage`) or reset each session? (Default: persist last rect — cheap and creator-friendly.)
- BG audio for Photos images (still image + mic only): allow optional music pick in v1.1, not v1.
