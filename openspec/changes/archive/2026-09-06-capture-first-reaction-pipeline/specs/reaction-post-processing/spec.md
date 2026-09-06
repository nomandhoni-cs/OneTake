## ADDED Requirements

### Requirement: Accurate sequence segmentation at export

The system SHALL segment the raw camera footage with
`VNGeneratePersonSegmentationRequest` at `.accurate` quality through
`VNSequenceRequestHandler`, picking the mask pixel format from
`supportedOutputPixelFormats()`. A first-30-frames fps probe SHALL
auto-downgrade to `.balanced` with a note when `.accurate` cannot sustain a
reasonable export pace. `VNGeneratePersonInstanceMaskRequest` SHALL NOT be used.

#### Scenario: Export uses accurate quality

- **WHEN** the export job runs on a capable device
- **THEN** segmentation runs at `.accurate` with cleaner edges than the old realtime `.balanced` path

#### Scenario: Slow device downgrades gracefully

- **WHEN** the fps probe shows `.accurate` is too slow
- **THEN** the job continues at `.balanced`, notes it in the result, and still completes

### Requirement: Deterministic composite render

The system SHALL render every camera frame through the existing compositor
with the frozen `ReactionStyle` snapshot (layout, presenter rect, outline),
reading BG video frames from an `AVAssetReader` (looping when the BG is
shorter, stopping at camera end when longer) or the static image for photo
BGs, and SHALL write 1080p30 SDR H.264 identical in framing to the capture
preview geometry.

#### Scenario: Short background loops seamlessly

- **WHEN** a 10-second BG backs a 30-second take
- **THEN** the BG loops under the full take with no gaps or frozen frames

#### Scenario: Style choices match preview framing

- **WHEN** the user framed a bottom-right circle PiP with cyan outline
- **THEN** the exported file shows that exact placement and outline

### Requirement: Offline lookahead audio mix

The system SHALL mix the mic track with the BG audio track sample-accurately
by presentation timestamps, driving the existing ducking curve with ~1 s of
envelope lookahead, and SHALL encode AAC 44.1 kHz mono. Photo BGs SHALL
produce mic-only audio. Mic mute SHALL be honored; BG metering independence is
preserved from the realtime behavior.

#### Scenario: Ducking anticipates speech

- **WHEN** speech starts after silence
- **THEN** the BG is already ducking at the first voiced sample with no reactive pump

#### Scenario: Photo background take has clean voice audio

- **WHEN** the BG is a photo
- **THEN** the file contains the full mic track with no BG component

### Requirement: Progress, cancel, retry, and temp lifecycle

The system SHALL show export progress (0–100%) with Cancel; cancel SHALL stop
readers/writer and delete temp files. Failure SHALL preserve the raw camera
file and offer Retry (re-run on the kept raw) or Discard. Success SHALL move
temp atomically into `Takes/`, delete the raw file, and save the
`Take(isReaction: true)`. A free-space precheck SHALL block export with an
explanatory alert when ~2× the take size is unavailable, and a background-task
assertion SHALL cover backgrounding mid-export.

#### Scenario: Cancel cleans up

- **WHEN** the user cancels at 40%
- **THEN** temp files are deleted, the raw file is kept, and the UI returns to the studio

#### Scenario: Failure offers retry, not data loss

- **WHEN** export fails (e.g., OS kills the job in background)
- **THEN** the raw file persists and reopening offers Retry with the same style snapshot

#### Scenario: Insufficient disk blocks early

- **WHEN** free space is below ~2× the estimated output
- **THEN** export does not start and an alert explains how much space is needed

### Requirement: Honest framing preview during capture

The system SHALL preview the live camera as an unmasked presenter rectangle
over the playing BG (no inference during capture), with layout/outline
controls adjusting geometry live. No preview element SHALL imply a cutout that
isn't computed until export.

#### Scenario: Preview shows placement, not cutout

- **WHEN** the user frames Circle PiP bottom-right while previewing
- **THEN** the rectangle sits bottom-right and the exported cutout lands in the same place
