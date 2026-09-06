## Why

OneTake creators currently need CapCut/Premiere to overlay their face on a background video for reactions. A native, offline Reaction Studio — front-camera person cutout composited over a user-picked background video/image with teleprompter notes — lets them react, read, and export a finished video in a single take, which is OneTake's core promise.

## What Changes

- Studio tab becomes a 2-card mode picker: **Teleprompter** (existing flow) and **Reaction** (new), each opening a full-screen camera interface that hides the bottom tab bar.
- New Reaction capture mode: front-camera person segmentation (`VNGeneratePersonSegmentationRequest` on ANE) composited over a user-selected background (Photos video/image) via CoreImage `CIBlendWithMask` on the Metal GPU, previewed live and recorded to a single MP4 `Take` via `AVAssetWriter`.
- Cutout customization: Circle PiP (Loom-style) / Full-silhouette / Split-screen layouts, draggable + pinch-scalable presenter, optional outline glow (white/cyan/yellow/red/off).
- Background controls: pick/replace BG media, restart BG, BG volume slider, flip camera-side mirror toggle; web-URL import and slide-deck BG explicitly out of scope for v1.
- Audio: mic + BG-track mix with smart voice ducking (BG −70% while speaking, smooth fade back) and dual level meters (mic vs BG).
- Teleprompter integration: optional script picker (defaults to freestyle/"No script") with frosted lens-anchored prompter overlaying the reaction composite; pause freezes scroll per existing semantics.
- Composited takes flow into the existing My Takes pipeline (blade/trim/LUT/export) unchanged; HDR falls back to SDR in reaction mode v1.

## Capabilities

### New Capabilities

- `reaction-studio`: Reaction capture mode — mode picker entry, BG source selection, Vision segmentation + CoreImage compositing, layout/outline/gesture customization, BG transport + volume + ducking meters, full-screen recording to composited MP4 Take with optional script overlay.

### Modified Capabilities

- `unified-tab-navigation`: Studio tab shows mode picker instead of camera directly; both modes present full-screen (tab bar hidden) with dismiss back to picker.
- `capture-engine`: Adds composited `AVAssetWriter` recording path alongside existing `AVCaptureMovieFileOutput` path; documents format/HDR/permission behavior in reaction mode.
- `prompter-studio`: Prompter overlay SHALL also work over reaction composite with optional-script semantics (freestyle default).

## Impact

- Affected code: `RootTabView.swift` / `StudioTab`, `Features/Studio/` (new `ReactionStudioView`, `ReactionCaptureService`/`Compositor`, BG picker, cutout controls), `Core/Export` (no change — composited file is a normal `Take`), `Take` model (optional `isReaction` flag / `backgroundAssetID`, additive migration).
- Dependencies: Vision, CoreImage/Metal, AVFoundation (`AVPlayerItemVideoOutput`, `AVAssetWriter`), Photos picker — all first-party, offline, no new packages.
- Risks: ANE/GPU thermal load (reuse `ThermalMonitor`), BG-video DRM (Photos-only v1, no protected streams), portrait segmentation quality on older devices (graceful fallback to circle-PiP without mask).
