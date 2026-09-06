## ADDED Requirements

### Requirement: Composited reaction recording path

The system SHALL provide a reaction recording path using `AVCaptureVideoDataOutput` + `AVCaptureAudioDataOutput` with Vision segmentation, CoreImage GPU compositing, and `AVAssetWriter` encoding (H.264, 1080p30 SDR v1), alongside and without altering the existing `AVCaptureMovieFileOutput` teleprompter path. The BG `AVPlayer` clock SHALL be the presentation-time master so audio/video sync stays within 80ms over a 5-minute reaction. Camera format controls (resolution / frame rate / HDR) SHALL remain in the Studio settings bottom sheet and stay disabled while recording or paused with the existing "Stop recording to change camera format" caption; HDR requests in reaction mode SHALL record SDR with an "SDR in Reaction v1" caption.

#### Scenario: Reaction record and stop produce single MP4

- **WHEN** the user records a 30-second reaction and taps Stop
- **THEN** a single MP4 file is finalized containing composited video plus mixed mic/BG audio with no orphan segments

#### Scenario: Teleprompter path unchanged

- **WHEN** the user records in Teleprompter mode
- **THEN** capture uses `AVCaptureMovieFileOutput` exactly as before with no behavior change

#### Scenario: Reaction pause resumes background in sync

- **WHEN** the user pauses then resumes a reaction recording
- **THEN** the background video pauses and resumes with the take, and the final file is a single merged MP4 with A/V sync preserved
