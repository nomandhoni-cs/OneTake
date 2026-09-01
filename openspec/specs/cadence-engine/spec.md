# cadence-engine Specification

## Purpose
TBD - created by archiving change modern-apple-api-features. Update Purpose after archive.
## Requirements
### Requirement: Real-time word count
The system SHALL compute word count from the script body in real time, updating synchronously as the user types via an `@Observable` view model.

#### Scenario: Word count increments while typing
- **WHEN** user types additional words into the editor
- **THEN** the displayed word count increments immediately without debounce visible to the user

#### Scenario: Empty body shows zero words
- **WHEN** script body is empty or whitespace-only
- **THEN** word count is 0

#### Scenario: Word definition
- **WHEN** body contains punctuation, line breaks, and multiple spaces
- **THEN** word count counts sequences of non-whitespace characters separated by whitespace (e.g., "hello,  world\nnew" = 3)

### Requirement: Duration estimation at 130 wpm
The system SHALL convert word count to estimated speaking duration using a 130 words-per-minute baseline and display it as `mm:ss`.

#### Scenario: Duration calculation
- **WHEN** script has 130 words
- **THEN** estimated duration displays as "1:00" (1 minute)

#### Scenario: Duration updates live
- **WHEN** user edits body changing word count from 65 to 260
- **THEN** duration updates from "0:30" to "2:00" in real time alongside word count

#### Scenario: Duration formatting for short scripts
- **WHEN** script has 13 words
- **THEN** duration displays as "0:06" (6 seconds, rounded to nearest second)

### Requirement: Observable state propagation
The system SHALL expose word count and duration through an `@Observable` macro view model so any SwiftUI view observing it invalidates only on relevant changes.

#### Scenario: Toolbar reflects latest cadence without manual refresh
- **WHEN** the `@Observable` cadence model's word count changes
- **THEN** the editor toolbar and any other subscribed view re-render with the new values automatically

#### Scenario: No stale reads after rapid typing
- **WHEN** user types rapidly for 5 seconds
- **THEN** the final displayed word count and duration match the final body text with no dropped updates

