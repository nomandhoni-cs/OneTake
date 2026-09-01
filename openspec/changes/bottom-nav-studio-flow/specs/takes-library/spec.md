## ADDED Requirements

### Requirement: My Takes aggregated list
The system SHALL display all `Take` records aggregated across scripts in the My Takes tab, reverse-chronological by `createdAt`, grouped by day section headers (Today / Yesterday / date), showing for each row the resolved script title, duration, thumbnail placeholder, trim indicator if `trimRange != nil`, and LUT badge if `lutPreset != natural`.

#### Scenario: My Takes renders grouped list
- **WHEN** the user opens My Takes with 5 takes across 3 days
- **THEN** the list shows day-grouped sections with correct headers and rows in reverse-chronological order

#### Scenario: Script title resolves correctly
- **WHEN** a take’s `scriptID` matches a `Script.title`
- **THEN** the row shows that title; when no match (deleted script), it shows “Freestyle / No script”

### Requirement: Search and filter
The system SHALL provide `.searchable` filtering over resolved script title (case-insensitive) within My Takes; an empty result SHALL show `ContentUnavailableView.search` and invalid file paths SHALL be visually indicated (file-missing badge) but not crash the list.

#### Scenario: Search filters takes
- **WHEN** the user types “demo” in My Takes search
- **THEN** only takes whose script title contains “demo” remain visible

#### Scenario: Missing file indicated
- **WHEN** a take’s `fileURL` does not exist on disk
- **THEN** the row shows a “File missing” indicator and tapping shows an alert instead of crashing

### Requirement: Empty, error, and swipe actions
The system SHALL show `ContentUnavailableView` when there are zero takes with a CTA to “Record your first take” (opens Studio), and SHALL expose swipe actions: trailing Delete (destructive) and leading Edit (opens Review in edit mode). `ContentUnavailableView` SHALL be used for all empty states (no takes, no search results).

#### Scenario: Empty My Takes
- **WHEN** the store contains zero takes
- **THEN** `ContentUnavailableView` shows “No takes yet” with a button that presents Studio

#### Scenario: Delete take via swipe
- **WHEN** the user swipes trailing Delete on a take
- **THEN** the system deletes the file at `fileURL` if present, deletes the `Take` from `ModelContext`, and animates removal without orphaning segments

#### Scenario: Edit take via swipe
- **WHEN** the user swipes leading Edit
- **THEN** the system pushes `ReviewView(take:)` onto the My Takes stack in edit mode

### Requirement: Navigation to Review
The system SHALL navigate from My Takes to `ReviewView(take:)` for the selected take on row tap; Review SHALL display the existing preview/trim/LUT/save/share flows unchanged beyond being pushed on the My Takes stack.

#### Scenario: Tap take opens Review
- **WHEN** the user taps a take row
- **THEN** Review is pushed with `VideoPlayer` playing that take’s file and the back gesture returns to My Takes
