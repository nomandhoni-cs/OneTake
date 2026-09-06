## MODIFIED Requirements

### Requirement: Blade split at playhead
The system SHALL provide a blade (scissors) tool on the `TrimScrubberView` timeline that splits the current `Take` at the playhead `CMTime` into explicit source ranges; the playhead position is clamped to `(trimStart + 0.1s, trimEnd - 0.1s)` and duplicate cuts within 0.1s are ignored. Splits SHALL accumulate: repeated splits produce N ordered ranges, each split auto-selects the segment containing the cut, and every split pushes the prior ranges to the Undo stack.

#### Scenario: Split at playhead creates segments
- **WHEN** the user positions the playhead at 8.0s in a 20s take and taps Blade
- **THEN** the take gains ranges [0-8s, 8-20s] and the timeline renders two segments with a visible divider

#### Scenario: Repeated splits produce N chunks
- **WHEN** the user blades at 5s, 12s, and 18s in a 25s take
- **THEN** the timeline renders four segments with three dividers and each split remains undoable in order

#### Scenario: Blade disabled at ends
- **WHEN** the playhead is at the start handle or end handle
- **THEN** the Blade button is disabled and shows an inactive state

#### Scenario: Duplicate split ignored
- **WHEN** the user blades at 8.0s twice
- **THEN** only one cut at 8.0s exists

### Requirement: Segment selection and deletion
The system SHALL allow selecting any segment by tap (first, middle, or last) and deleting the selected segment whenever more than one segment exists; deletion removes that segment's source range outright (no shifting arithmetic), updates `Take` duration to the sum of surviving segments, and sorts remaining ranges thereafter. Deleting an edge segment SHALL behave like trimming to its surviving neighbor. The sole surviving segment SHALL never be deletable.

#### Scenario: Delete interior segment compacts timeline
- **WHEN** a take holds ranges [0-5s, 5-12s, 12-20s] and the user deletes the middle segment [5-12s]
- **THEN** the timeline shows [0-5s, 12-20s], take duration becomes 13s, and export contains exactly those 13 seconds

#### Scenario: Delete first segment trims to neighbor
- **WHEN** a take holds ranges [0-5s, 5-20s] and the user deletes segment 1
- **THEN** the timeline shows [5-20s] with duration 15s and export starts at source 5s

#### Scenario: Delete last remaining segment denied
- **WHEN** the take has only one segment (no cuts)
- **THEN** Delete is disabled

#### Scenario: Delete updates persistence
- **WHEN** a segment is deleted
- **THEN** `Take` ranges are persisted via SwiftData and the change survives relaunch

## ADDED Requirements

### Requirement: Explicit blade segment store
The system SHALL persist blade edits as explicit source ranges (`Take.segments: [BladeSegment]?`, each with start + duration seconds) instead of deriving deletions from cut positions; `bladeSegments()` SHALL prefer stored ranges with legacy cut-derivation fallback for takes predating the field, `bladeCuts` SHALL stay synced as internal boundaries for the scrubber dividers, and the Undo stack SHALL snapshot ranges.

#### Scenario: Legacy take derives ranges on first edit
- **WHEN** a take with only `bladeCuts` [5, 12] is opened and split at 18s
- **THEN** stored ranges materialize as [0-5s, 5-12s, 12-18s, 18-20s] and subsequent edits operate on ranges

#### Scenario: Undo restores ranges
- **WHEN** the user splits at 7s, then taps Undo
- **THEN** the prior ranges return and the timeline restores its segment count

### Requirement: Timeline segment framing
The system SHALL frame every timeline segment with its index/total and duration, render 2pt cut dividers at each boundary, outline the selected segment distinctly, and render the playhead clamped so it never hides under a trim handle; the selected-segment readout SHALL show `Segment i/N • m:ss`.

#### Scenario: Segments carry identity
- **WHEN** a take holds three segments and segment 2 is selected
- **THEN** the timeline shows three framed regions, dividers at both boundaries, a highlight on the middle segment, and the readout "Segment 2/3 • 0:07"

#### Scenario: Playhead never hides under handles
- **WHEN** the playhead approaches a trim handle
- **THEN** it clamps visibly adjacent instead of rendering beneath the handle
