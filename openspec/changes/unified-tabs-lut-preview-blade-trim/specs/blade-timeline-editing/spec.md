## ADDED Requirements

### Requirement: Blade split at playhead
The system SHALL provide a blade (scissors) tool on the `TrimScrubberView` timeline that splits the current `Take` into segments at the playhead `CMTime`; the playhead position is clamped to `(trimStart + 0.1s, trimEnd - 0.1s)` and duplicate cuts within 0.1s are ignored.

#### Scenario: Split at playhead creates segments
- **WHEN** the user positions the playhead at 8.0s in a 20s take and taps Blade
- **THEN** the take gains a cut at 8.0s and the timeline renders two segments [0-8s, 8-20s] with a visible divider

#### Scenario: Blade disabled at ends
- **WHEN** the playhead is at the start handle or end handle
- **THEN** the Blade button is disabled and shows an inactive state

#### Scenario: Duplicate split ignored
- **WHEN** the user blades at 8.0s twice
- **THEN** only one cut at 8.0s exists

### Requirement: Segment selection and deletion
The system SHALL allow selecting a segment by tap and deleting the selected interior segment; deletion compacts the timeline by removing that segment's interval, updates `Take` duration to the sum of surviving segments, and sorts `bladeCuts` thereafter.

#### Scenario: Delete interior segment compacts timeline
- **WHEN** a take has cuts at [5s, 12s] (three segments) and the user deletes the middle segment [5-12s]
- **THEN** the timeline shows two segments and the take duration becomes `(5s + (duration-12s))` with cuts compacted to [5s]

#### Scenario: Delete last remaining segment denied
- **WHEN** the take has only one segment (no cuts)
- **THEN** Delete is disabled

#### Scenario: Delete updates persistence
- **WHEN** a segment is deleted
- **THEN** `Take.bladeCuts` is persisted via SwiftData and the change survives relaunch

### Requirement: Blade state integrates with trim and undo
The system SHALL keep `bladeCuts` clamped within the current `trimRange`; changing trim handles that would orphan cuts SHALL prune out-of-range cuts. The blade edit session SHALL support Undo for split and delete actions within the Review session.

#### Scenario: Trim change prunes cuts
- **WHEN** the user trims start to 6s while cuts exist at [3s, 10s]
- **THEN** the cut at 3s is removed and only 10s remains

#### Scenario: Undo after blade actions
- **WHEN** the user splits at 7s, then taps Undo
- **THEN** the cut at 7s is removed and the timeline returns to its prior segment count

### Requirement: Blade composition on export and playback
The system SHALL export blade-edited takes via `AVMutableComposition` inserting each surviving segment's `timeRange` from the source asset, and attach an `AVVideoComposition` with `CIFilter.colorCube` only when `lutPreset != .natural`; passthrough preset is used when no LUT is active. Preview playback SHALL honor blade cuts via the same composition.

#### Scenario: Export with blades and LUT in one pass
- **WHEN** the user trimmed, split at 4s, deleted a segment, and selected Cinematic Contrast, then taps Save
- **THEN** the exported file contains the composed surviving segments graded by that LUT in a single export pass

#### Scenario: Export with blades and Natural uses passthrough
- **WHEN** blade cuts exist but LUT is Natural
- **THEN** the export uses `AVAssetExportSession(preset: .passthrough)` over the composition without a video composition filter

#### Scenario: Blade preview matches export
- **WHEN** a take has blade cuts
- **THEN** `VideoPlayer` preview plays the same composed timeline that export will produce
