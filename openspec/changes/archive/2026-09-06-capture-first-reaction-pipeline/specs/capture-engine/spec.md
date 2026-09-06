## ADDED Requirements

### Requirement: Reaction capture via standard movie-file path

The system SHALL record reaction camera footage (front camera + mic) with
`AVCaptureMovieFileOutput` under teleprompter semantics — pause/resume with
single merged file and no orphans, backgrounding/interruption auto-finalize,
and format controls disabled while recording or paused — while the BG media
plays independently for the performer. The realtime composited-writer
recording path SHALL NOT be used. BG transport (restart/replace) SHALL be
preview-only and disabled during recording so the camera-to-BG timeline mapping
stays linear.

#### Scenario: Reaction pause behaves like teleprompter pause

- **WHEN** the user pauses then resumes a reaction recording
- **THEN** the raw camera file pauses and resumes with prompter scroll frozen, producing one continuous file

#### Scenario: Backgrounding finalizes safely

- **WHEN** the app backgrounds mid-reaction-recording
- **THEN** the raw file finalizes without corruption and offers processing on return

#### Scenario: BG controls lock during recording

- **WHEN** recording starts with a BG video playing
- **THEN** Restart/replace BG controls disable with a caption and re-enable on stop
