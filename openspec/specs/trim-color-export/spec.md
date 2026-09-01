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
The system SHALL apply `.cube` 3D LUT color tables through `CIFilter.colorCube` running on the Metal GPU, providing four built-in presets: Natural, Warm Studio, Cinematic Contrast, Clean Monochrome, and SHALL render a color preview swatch per preset in the picker.

#### Scenario: User selects Warm Studio preset
- **WHEN** user selects Warm Studio before export
- **THEN** the system loads the Warm Studio `cubeData` (64×64×64) and applies `CIFilter.colorCube(cubeDimension: 64)` via `CIContext(mtlDevice:)` to the exported frames

#### Scenario: Natural is identity
- **WHEN** user selects Natural
- **THEN** the output matches the input frames (no visible color shift) and the system may skip the filter pass for performance; the preview swatch shows neutral gray

#### Scenario: Monochrome produces grayscale
- **WHEN** user selects Clean Monochrome
- **THEN** the exported video renders as grayscale with preserved luminance

#### Scenario: Trim and LUT combined
- **WHEN** user both trims and selects Cinematic Contrast
- **THEN** the system composes `timeRange` trimming and `colorCube` filtering in a single export pass (using `AVMutableComposition` + `CIImage` pipeline or `AVVideoComposition` with `CIFilter`) and produces a correctly trimmed and graded file

#### Scenario: LUT picker shows rendered swatches
- **WHEN** the user opens the LUT picker in Review
- **THEN** each row shows a 40×24 rendered swatch of that preset's transform (Natural = neutral gray, others tinted per their `.cube`) plus the display name; swatches are cached and regenerate when `.cube` data changes

#### Scenario: Swatch fallback
- **WHEN** a `.cube` file is missing or `cubeData` is nil
- **THEN** the row shows a tinted placeholder swatch and the export falls back to Natural behavior for that preset

### Requirement: Grouped edit menus
The system SHALL group My Takes row actions and Review toolbar actions into `Menu` sections: "Adjust" (Trim, Blade/Split at Playhead, Delete Selected Segment) and "Color" (LUT) and "Output" (Save to Photos, Share), consistently across swipe trailing menu, context menu, and the Review toolbar ellipsis. Disabled states SHALL reflect current preconditions (e.g., Blade disabled at ends, Delete disabled with no selection, Save disabled while exporting).

#### Scenario: Row swipe menu shows grouped sections
- **WHEN** the user swipes a take row or long-presses for the context menu
- **THEN** the menu shows Section "Adjust" with Trim / Blade / Delete, Section "Color" with LUT submenu, Section "Output" with Save/Share, in that order

#### Scenario: Review toolbar ellipsis mirrors row menu
- **WHEN** the user opens the Review toolbar `...` menu
- **THEN** it shows the same three sections and disabled-state logic as the My Takes row menu

### Requirement: Direct Camera Roll save with cleanup
The system SHALL save the processed MP4 directly to Apple Photos via `PHPhotoLibrary` with `PHAssetChangeRequest.creationRequestForAssetFromVideo`, requesting `.addOnly` authorization, and clean up sandbox cache after success. The action SHALL be reachable both from Review (Save button) and from My Takes via the Edit → Review flow; on success the source sandbox file SHALL be deleted to preserve disk space, and the take’s `relativeFilePath` SHALL be updated atomically to the new file if the user chose “Replace”.

#### Scenario: Successful save to Photos
- **WHEN** user taps Save and grants Photos add-only permission
- **THEN** the video appears in the Photos library and the sandbox source file is deleted to preserve disk space

#### Scenario: Photos permission denied
- **WHEN** Photos permission is denied
- **THEN** the system shows an explanatory alert with a button to open Settings and does not delete the sandbox file

#### Scenario: Sandbox cleanup preserves original on failure
- **WHEN** Photos save fails
- **THEN** the sandbox file remains intact for retry and is not deleted

#### Scenario: Save reachable from My Takes Edit
- **WHEN** the user opens a Take from My Takes → Edit → Re-export then Save
- **THEN** the newly exported file is saved to Photos and the Take record is updated per the user’s “Save as new” or “Replace” choice

### Requirement: Native iOS Share Sheet
The system SHALL provide quick-share via SwiftUI `ShareLink` to AirDrop, Messages, Instagram, TikTok, etc., without leaving the app.

#### Scenario: Share sheet presents native destinations
- **WHEN** user taps Share on a processed take
- **THEN** `ShareLink(item: outputURL)` presents the native share sheet with available destinations including AirDrop and installed social apps

#### Scenario: Share uses exported file
- **WHEN** user trimmed or graded the take
- **THEN** the shared file is the processed output, not the raw original

### Requirement: Edit, delete, and re-export from My Takes
The system SHALL allow editing an existing Take from My Takes by reopening `ReviewView` in edit mode to re-trim (`CMTimeRange` dual-handle) and/or change LUT, then re-export via the existing `ExportService` pipeline (passthrough or `CIFilter.colorCube`); re-export SHALL produce either a new `Take` (“Save as New Take”) preserving the original file or replace the existing `Take`’s file atomically (“Replace”), and delete from My Takes swipe SHALL remove the `Take` and its file (and any orphan segments) with confirmation.

#### Scenario: Re-trim and save as new take
- **WHEN** the user edits a Take, adjusts trim handles to a new range, and chooses “Save as New Take”
- **THEN** a new `Take` is inserted with the new file, the original Take and file remain unchanged, and both appear in My Takes

#### Scenario: Replace existing take
- **WHEN** the user edits a Take and chooses “Replace”
- **THEN** the original Take’s `relativeFilePath` is updated to the new file, the old file is deleted, and no duplicate take is created

#### Scenario: Delete from My Takes
- **WHEN** the user deletes a Take via swipe in My Takes and confirms
- **THEN** the file at `fileURL` and any segment temp directory are removed, the record is deleted, and the list animates removal

#### Scenario: Re-export failure retains original
- **WHEN** re-export fails (disk full, invalid range)
- **THEN** the system shows an error alert, retains the original file and record, and allows retry
