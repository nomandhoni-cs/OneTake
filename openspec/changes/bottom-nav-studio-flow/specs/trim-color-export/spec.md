## MODIFIED Requirements

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

## ADDED Requirements

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
