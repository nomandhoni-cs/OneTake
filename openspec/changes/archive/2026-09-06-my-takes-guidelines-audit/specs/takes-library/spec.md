## MODIFIED Requirements

### Requirement: Search and filter
The system SHALL provide `.searchable` filtering over resolved script title (case-insensitive) within My Takes, composed (AND) with a visible scope bar (All / Reactions); the hidden `"reaction"` keyword is removed. Day headers SHALL use relative date formatting (localized Today/Yesterday). An empty result SHALL show `ContentUnavailableView.search` and invalid file paths SHALL be visually indicated (file-missing badge) but not crash the list.

#### Scenario: Scope filters reactions
- **WHEN** the user picks the Reactions scope in My Takes search
- **THEN** only takes with `isReaction == true` remain, further narrowed by any typed title text

#### Scenario: Day headers localize
- **WHEN** the device locale is not English and a take was created today
- **THEN** its section header shows the locale's relative day name, not the English word "Today"

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

## ADDED Requirements

### Requirement: Context menu contract
The system SHALL expose row actions in a grouped context menu with sections Adjust (Trim, Blade Split at Middle), Color (LUT submenu with swatches), Output (Share when the file exists), and Destructive last (Delete Last Segment, Delete Take). Blade Split SHALL target trim-middle and be disabled when the effective trim length is under 1.1s; Delete Last Segment SHALL be disabled with fewer than two segments and SHALL require confirmation stating the loss is permanent.

#### Scenario: Segment delete confirms
- **WHEN** the user taps Delete Last Segment on a 3-segment take
- **THEN** a confirmation dialog appears; confirming removes the last source range and saves, canceling leaves the take untouched

#### Scenario: Split targets middle
- **WHEN** the user taps Blade Split at Middle on an untrimmed 20s take
- **THEN** the take gains ranges [0-10s, 10-20s]
