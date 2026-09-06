# reaction-studio Specification

## Purpose
Reaction studio experience: Photos background selection, framing-only preview with layout/outline controls, voice-ducked audio, script overlay option, and standard Take production via the post-capture export job.

## Requirements
### Requirement: Reaction background source selection

The system SHALL let the user pick a background from the Photos library (video or image) via `PHPickerViewController`, preview it full-frame in Reaction mode, replace it at any time while not recording, and restart video backgrounds from the beginning. Protected/DRM content that cannot be read SHALL be rejected at pick time with an explanatory alert. Web-URL import and slide-deck backgrounds are out of scope for v1.

#### Scenario: Pick a background video

- **WHEN** the user taps BG Media and selects a Photos video
- **THEN** the background plays full-frame muted-preview behind the cutout controls and is ready to record

#### Scenario: Replace background while previewing

- **WHEN** the user picks a different photo while in reaction preview (not recording)
- **THEN** the new image replaces the background immediately without restarting the camera session

#### Scenario: Restart background video

- **WHEN** the user taps Restart BG during preview or before recording
- **THEN** the background video seeks to zero and resumes playing from the start

#### Scenario: Protected content rejected

- **WHEN** the user picks a DRM-protected video that `AVAssetReader` cannot read
- **THEN** the system shows an alert explaining the clip cannot be used and keeps the previous background

### Requirement: Person cutout compositing in post-capture export (framing-only preview)

The system SHALL NOT run segmentation or compositing live during capture; the Reaction preview SHALL show the live camera as an unmasked presenter rectangle over the playing BG for framing only, with no inference on device during recording. Person segmentation (`VNGeneratePersonSegmentationRequest` at `.accurate` quality via `VNSequenceRequestHandler`) and CoreImage GPU compositing SHALL happen in the post-capture export job using the frozen `ReactionStyle` snapshot, producing framing identical to the preview geometry.

#### Scenario: Framing-only live preview

- **WHEN** the user enters Reaction mode with a background selected and grants camera permission
- **THEN** the preview shows their unmasked camera rectangle over the playing background for placement, with no cutout computed until export

#### Scenario: Exported cutout matches framed placement

- **WHEN** the user frames a Circle PiP bottom-right and completes the export job
- **THEN** the saved MP4 shows the `.accurate`-quality cutout at that exact placement, layout, and outline

#### Scenario: No inference cost during capture

- **WHEN** the user records on an older device that could not sustain live segmentation
- **THEN** capture still runs at full camera frame rate with no fallback caption needed, since segmentation runs offline at export

### Requirement: Cutout layout, placement, and outline

The system SHALL provide three layout modes — Full Silhouette (full-frame cutout), Circle PiP (Loom-style bubble), and Split Screen (side-by-side) — with a draggable, pinch-scalable presenter rect (persisted across sessions) and an optional outline glow (off/white/cyan/yellow/red). Layout and outline changes SHALL apply live during preview and recording without restarting capture.

#### Scenario: Switch layout live

- **WHEN** the user switches from Silhouette to Circle PiP while recording
- **THEN** the composite switches immediately, capture continues uninterrupted, and the change is reflected in the output file

#### Scenario: Drag and scale presenter

- **WHEN** the user drags the cutout bubble to bottom-right and pinches to enlarge it
- **THEN** the cutout renders at the new position/scale live and the placement persists on next launch

#### Scenario: Outline color selection

- **WHEN** the user selects the cyan outline
- **THEN** the presenter's silhouette renders with a cyan glow in preview and in the recorded file

### Requirement: Reaction audio mixing with voice ducking and dual meters

The system SHALL mix microphone audio with the background video's audio track, automatically ducking BG volume to 30% while the user speaks (fast attack, smooth ~800ms release) with a user-toggleable Duck switch and BG volume slider, and SHALL display independent live level meters for Mic and BG. Mic mute state SHALL never affect BG metering.

#### Scenario: Voice ducks background

- **WHEN** the user speaks into the mic while a loud background video plays with Duck ON
- **THEN** the BG level audibly drops to ~30% and fades back up within a second after the user pauses

#### Scenario: Duck toggle off

- **WHEN** the user turns Duck Voice OFF
- **THEN** background volume follows the BG slider only and speaking causes no automatic change

#### Scenario: Dual meters move independently

- **WHEN** the mic is muted and the background video plays
- **THEN** the BG meter animates while the mic meter rests at zero

### Requirement: Reaction recording produces a standard Take via export job

The system SHALL record reaction camera footage via the standard `AVCaptureMovieFileOutput` movie-file path (front camera + mic, 1080p30 SDR v1) under teleprompter pause/resume and backgrounding/interruption semantics, then produce the composited file in the post-capture export job (H.264 with mixed mic/BG audio) saved as a normal `Take` (`isReaction = true`, `backgroundAssetLocalID` recorded when available). The realtime `AVAssetWriter` composited-recording path SHALL NOT be used. The resulting Take SHALL support the full downstream pipeline (blade, trim, LUT, export, Photos save). HDR requests in reaction mode SHALL fall back to SDR with an explanatory caption.

#### Scenario: Reaction take appears in My Takes after export

- **WHEN** the user stops a reaction recording and the export job completes
- **THEN** a take with a reaction badge appears in My Takes and plays back the composite with mixed audio

#### Scenario: Reaction take supports blade and LUT export

- **WHEN** the user blade-splits and applies a LUT to a reaction take
- **THEN** trim, blade, color, and export behave exactly as for teleprompter takes

#### Scenario: HDR falls back to SDR in reaction mode

- **WHEN** HDR is enabled and the user enters Reaction mode
- **THEN** the composite exports in SDR and the settings show an "SDR in Reaction v1" caption
