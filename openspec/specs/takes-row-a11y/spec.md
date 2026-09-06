# takes-row-a11y Specification

## Purpose
VoiceOver contract for takes-library rows: each row reads as one unit. Split out during `my-takes-guidelines-audit`; see `takes-library` for list behavior.

## Requirements
### Requirement: Row accessibility
Each take row SHALL be a single VoiceOver element combining title, duration, badges, and date, with a hint describing the tap action; missing-file rows SHALL announce the missing state.

#### Scenario: Row reads as one unit
- **WHEN** VoiceOver focuses a trimmed, graded take row
- **THEN** it announces one label (title, duration, Trimmed, LUT name, date) and the hint "Opens review"

#### Scenario: Missing file announced
- **WHEN** VoiceOver focuses a row whose video file is gone
- **THEN** the label includes the missing-file state and the hint describes the alert-with-delete choice
