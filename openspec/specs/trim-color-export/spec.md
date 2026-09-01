# trim-color-export Specification

## Purpose
TBD - created by archiving change modern-apple-api-features. Update Purpose after archive.
## Requirements
### Requirement: Zero-delay in-app preview
The system SHALL provide instant playback of recorded takes using native `AVKit.VideoPlayer` without pre-rendering or transcoding delays.

#### Scenario: Immediate playback after recording
- **WHEN** user finishes recording a take
- **THEN** tapping Play starts `VideoPlayer` within 500 ms using the sandbox file URL with no export step required

#### Scenario: Preview supports scrubbing
- **WHEN** user drags the preview timeline
- **THEN** `AVPlayer` seeks to the requested time and resumes playback without re-encoding

### Requirement: Sub-second hardware stream trimming
The system SHALL provide a dual-handle timeline scrubber allowing users to trim the beginning and end of takes, performing trims via `CMTimeRange` stream passthrough in under one second without full-file re-encoding when no LUT is applied.

#### Scenario: Trim reduces duration via passthrough
- **WHEN** user sets handles to trim 2 s from start and 3 s from end of a 30 s take and confirms
- **THEN** the system exports via `AVAssetExportSession(preset: .passthrough)` with `timeRange = CMTimeRange(start: 2s, duration: 25s)` and completes in <1 s on iPhone 14+ class hardware

#### Scenario: Trim handles are constrained
- **WHEN** user drags handles
- **THEN** start handle cannot pass end handle, minimum trimmed duration is 1 s, and handles snap to frame boundaries where applicable

#### Scenario: Trim without LUT does not re-encode
- **WHEN** user trims but selects Natural (identity) LUT
- **THEN** the export uses passthrough (no `CIFilter` pass) preserving original quality and speed

#### Scenario: Trim export failure handling
- **WHEN** export fails (disk full, invalid `CMTimeRange`, session error)
- **THEN** the system shows an error alert, retains the original file, and allows retry without data loss

### Requirement: GPU 3D LUT color grading via CoreImage Metal
The system SHALL apply `.cube` 3D LUT color tables through `CIFilter.colorCube` running on the Metal GPU, providing four built-in presets: Natural, Warm Studio, Cinematic Contrast, Clean Monochrome.

#### Scenario: User selects Warm Studio preset
- **WHEN** user selects Warm Studio before export
- **THEN** the system loads the Warm Studio `cubeData` (64×64×64) and applies `CIFilter.colorCube(cubeDimension: 64)` via `CIContext(mtlDevice:)` to the exported frames

#### Scenario: Natural is identity
- **WHEN** user selects Natural
- **THEN** the output matches the input frames (no visible color shift) and the system may skip the filter pass for performance

#### Scenario: Monochrome produces grayscale
- **WHEN** user selects Clean Monochrome
- **THEN** the exported video renders as grayscale with preserved luminance

#### Scenario: Trim and LUT combined
- **WHEN** user both trims and selects Cinematic Contrast
- **THEN** the system composes `timeRange` trimming and `colorCube` filtering in a single export pass (using `AVMutableComposition` + `CIImage` pipeline or `AVVideoComposition` with `CIFilter`) and produces a correctly trimmed and graded file

### Requirement: Direct Camera Roll save with cleanup
The system SHALL save the processed MP4 directly to Apple Photos via `PHPhotoLibrary` with `PHAssetChangeRequest.creationRequestForAssetFromVideo`, requesting `.addOnly` authorization, and clean up sandbox cache after success.

#### Scenario: Successful save to Photos
- **WHEN** user taps Save and grants Photos add-only permission
- **THEN** the video appears in the Photos library and the sandbox source file is deleted to preserve disk space

#### Scenario: Photos permission denied
- **WHEN** Photos permission is denied
- **THEN** the system shows an explanatory alert with a button to open Settings and does not delete the sandbox file

#### Scenario: Sandbox cleanup preserves original on failure
- **WHEN** Photos save fails
- **THEN** the sandbox file remains intact for retry and is not deleted

### Requirement: Native iOS Share Sheet
The system SHALL provide quick-share via SwiftUI `ShareLink` to AirDrop, Messages, Instagram, TikTok, etc., without leaving the app.

#### Scenario: Share sheet presents native destinations
- **WHEN** user taps Share on a processed take
- **THEN** `ShareLink(item: outputURL)` presents the native share sheet with available destinations including AirDrop and installed social apps

#### Scenario: Share uses exported file
- **WHEN** user trimmed or graded the take
- **THEN** the shared file is the processed output, not the raw original

