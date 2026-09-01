## ADDED Requirements

### Requirement: SwiftData script persistence
The system SHALL persist scripts, drafts, and metadata using SwiftData `@Model` with instant autosave and zero network dependency. Each `Script` MUST store `id`, `title`, `body`, `createdAt`, `updatedAt`, and be queryable via `@Query`.

#### Scenario: Create script persists instantly
- **WHEN** user creates a new script with title and body
- **THEN** the script is inserted into `ModelContext`, saved without a loading spinner, and appears in the library on next query

#### Scenario: Edit script autosaves
- **WHEN** user edits the body of an existing script in the editor sheet
- **THEN** the system debounces and saves changes to SwiftData within 500 ms and updates `updatedAt`

#### Scenario: Offline persistence
- **WHEN** device is offline and user creates or edits a script
- **THEN** the script persists locally and remains available after app relaunch with no data loss

### Requirement: Script library list UI
The system SHALL display scripts in a SwiftUI `NavigationStack` using `.insetGrouped` list styling, supporting instant rendering with no loading spinners.

#### Scenario: Library renders grouped inset list
- **WHEN** user opens the app with existing scripts
- **THEN** the library shows scripts in an insetGrouped list with title, truncated body preview, and updated timestamp

#### Scenario: Empty library shows ContentUnavailableView
- **WHEN** the library contains zero scripts
- **THEN** the system presents `ContentUnavailableView` with a message and a call-to-action button to create the first script

### Requirement: Native search filtering
The system SHALL provide live text filtering of scripts using SwiftUI `.searchable()` over title and body.

#### Scenario: Search filters results
- **WHEN** user types a query into the search field
- **THEN** the list filters in real time to scripts whose title or body contains the query (case-insensitive)

#### Scenario: Empty search shows no-results state
- **WHEN** search query matches zero scripts
- **THEN** the system shows a no-results state with the query echoed and an option to clear search

### Requirement: Swipe actions for duplicate and delete
The system SHALL expose `.swipeActions` on each script row for instant duplication and deletion.

#### Scenario: Duplicate script via swipe
- **WHEN** user swipes a row and taps Duplicate
- **THEN** the system creates a new `Script` copying title (appended " copy") and body, inserts it, and shows it in the list

#### Scenario: Delete script via swipe
- **WHEN** user swipes a row and taps Delete
- **THEN** the system deletes the script from `ModelContext` with animation and removes it from the list

#### Scenario: Delete confirmation for destructive action
- **WHEN** user triggers delete
- **THEN** the system either deletes immediately with undo support or confirms via swipe-action confirmation, and never leaves orphaned `Take` records

### Requirement: Distraction-free editor sheet
The system SHALL present a native modal sheet for editing a script, including word-count telemetry in the toolbar and a 1-tap "Record with Prompter" launch action.

#### Scenario: Open editor sheet
- **WHEN** user taps a script row or the Create button
- **THEN** a sheet presents with a text editor focused on the body, toolbar showing word count, and a prominent "🎥 Record with Prompter" button

#### Scenario: Launch recording from editor
- **WHEN** user taps "Record with Prompter" in the editor sheet
- **THEN** the system dismisses or transitions the sheet and navigates to the Recording Studio with the current script loaded in the prompter

#### Scenario: Toolbar telemetry visible while editing
- **WHEN** user types in the editor
- **THEN** the toolbar continuously displays current word count and estimated duration (delegated to cadence-engine)
