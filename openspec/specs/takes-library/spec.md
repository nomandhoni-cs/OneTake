# takes-library Specification

## Purpose
Aggregated library of all Takes across scripts for the My Takes tab. Owns grouped-by-day reverse-chronological list, searchable filtering, ContentUnavailableView empty states, swipe actions, and navigation to Review. See also `trim-color-export` for edit/re-export flows and `blade-timeline-editing` for blade UI in Review.

## Requirements
### Requirement: My Takes aggregated list
The system SHALL display all `Take` records aggregated across scripts in the My Takes tab, reverse-chronological by `createdAt`, grouped by day section headers (Today / Yesterday / date), showing for each row the resolved script title, duration, thumbnail placeholder, trim indicator if `trimRange != nil`, and LUT badge if `lutPreset != natural`.

#### Scenario: My Takes renders grouped list
- **WHEN** the user opens My Takes with 5 takes across 3 days
- **THEN** the list shows day-grouped sections with correct headers and rows in reverse-chronological order

#### Scenario: Script title resolves correctly
- **WHEN** a take’s `scriptID` matches a `Script.title`
- **THEN** the row shows that title; when no match (deleted script), it shows “Freestyle / No script”

### Requirement: Search and filter
The system SHALL provide `.searchable` filtering over resolved script title (case-insensitive) within My Takes, composed (AND) with a visible scope bar (All / Reactions); day headers SHALL use relative date formatting (localized Today/Yesterday). An empty result SHALL show `ContentUnavailableView.search` and invalid file paths SHALL be visually indicated (file-missing badge) but not crash the list.

#### Scenario: Search filters takes
- **WHEN** the user types “demo” in My Takes search
- **THEN** only takes whose script title contains “demo” remain visible

#### Scenario: Scope filters reactions
- **WHEN** the user picks the Reactions scope in My Takes search
- **THEN** only takes with `isReaction == true` remain, further narrowed by any typed title text

#### Scenario: Day headers localize
- **WHEN** the device locale is not English and a take was created today
- **THEN** its section header shows the locale's relative day name, not the English word "Today"

#### Scenario: Missing file indicated
- **WHEN** a take’s `fileURL` does not exist on disk
- **THEN** the row shows a “File missing” indicator and tapping shows an alert instead of crashing

### Requirement: Empty, error, and swipe actions
The system SHALL show `ContentUnavailableView` when there are zero takes with a CTA to “Record your first take” (opens Studio), and SHALL expose swipe actions: trailing Delete (destructive, confirmed) and leading Edit (opens Review in edit mode). `ContentUnavailableView` SHALL be used for all empty states (no takes, no search results).

#### Scenario: Empty My Takes
- **WHEN** the store contains zero takes
- **THEN** `ContentUnavailableView` shows “No takes yet” with a button that presents Studio

#### Scenario: Delete take via swipe
- **WHEN** the user swipes trailing Delete on a take
- **THEN** a confirmation appears, and on confirm the system deletes the file at `fileURL` if present, deletes the `Take` from `ModelContext`, and animates removal without orphaning segments

#### Scenario: Edit take via swipe
- **WHEN** the user swipes leading Edit
- **THEN** the system pushes `ReviewView(take:)` onto the My Takes stack in edit mode

### Requirement: Context menu contract
The system SHALL expose row actions in a grouped context menu with sections Adjust (Trim, Blade Split at Middle), Color (LUT submenu with swatches), Output (Share when the file exists), and Destructive last (Delete Last Segment, Delete Take). Blade Split SHALL target trim-middle and be disabled when the effective trim length is under 1.1s; Delete Last Segment SHALL be disabled with fewer than two segments and SHALL require confirmation stating the loss is permanent.

#### Scenario: Segment delete confirms
- **WHEN** the user taps Delete Last Segment on a 3-segment take
- **THEN** a confirmation dialog appears; confirming removes the last source range and saves, canceling leaves the take untouched

#### Scenario: Split targets middle
- **WHEN** the user taps Blade Split at Middle on an untrimmed 20s take
- **THEN** the take gains ranges [0-10s, 10-20s]

### Requirement: Navigation to Review
The system SHALL navigate from My Takes to `ReviewView(take:)` for the selected take on row tap; Review SHALL display the existing preview/trim/LUT/save/share flows unchanged beyond being pushed on the My Takes stack.

#### Scenario: Tap take opens Review
- **WHEN** the user taps a take row
- **THEN** Review is pushed with `VideoPlayer` playing that take’s file and the back gesture returns to My Takes
