# script-workspace Specification

## Purpose
TBD - created by archiving change modern-apple-api-features. Update Purpose after archive.
## Requirements
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

### Requirement: Script categories data model
The system SHALL support user-created script categories via a `ScriptCategory` SwiftData `@Model` (id, name, symbolName, createdAt) with a many-to-one optional relationship from `Script.category`; deleting a category SHALL nullify (not delete) member scripts, and deleting a script SHALL leave its category intact. Renaming a category SHALL propagate to every member script.

#### Scenario: Assign script to category persists
- **WHEN** a user assigns a script to a category and saves
- **THEN** the script queries with `category` set from both directions (`category.scripts`, `script.category`) with no orphaned duplicates

#### Scenario: Delete category keeps scripts
- **WHEN** a user deletes a category holding N scripts
- **THEN** all N scripts survive and render as uncategorized; no `Script` row is removed

#### Scenario: Rename propagates
- **WHEN** a category is renamed in the manage sheet
- **THEN** every member script's badge, section header, and Studio selector entry reflect the new name immediately

### Requirement: Category management UI
The system SHALL provide a manage-categories sheet (create with name + icon, rename, restyle icon, delete with confirmation) reachable from the Scripts tab; the delete confirmation SHALL state how many scripts will become uncategorized.

#### Scenario: Create category with icon
- **WHEN** the user types a name, picks an icon, and taps add
- **THEN** the category appears in the list with its icon and a live member count

#### Scenario: Delete confirmation reports impact
- **WHEN** the user swipes delete on a category
- **THEN** a confirmation dialog reports "N scripts will become uncategorized" before any deletion occurs

### Requirement: Library filter chips and sections
The Scripts tab SHALL show a horizontally scrolling chip bar ("All" + one per category with member counts) when categories exist, filtering the list live; with zero categories and existing scripts it SHALL show a single "Add Category" entry instead. With no active filter or search, scripts SHALL be grouped into category sections plus an "Uncategorized" section.

#### Scenario: Filter by category chip
- **WHEN** the user taps a category chip
- **THEN** the list shows only that category's scripts and an empty result renders a category-specific empty state

#### Scenario: Grouped sections when unfiltered
- **WHEN** the library renders with categories in use and no filter/search active
- **THEN** scripts render under per-category section headers (icon, name, count) followed by an "Uncategorized" section

### Requirement: Row and editor category affordances
Each script row SHALL show its category badge and expose a context menu "Move to Category" submenu (plus duplicate/delete); the editor sheet SHALL show a category picker bar that can reassign, clear, or create a new category inline; new scripts created under an active filter SHALL inherit that category; duplicates SHALL copy the source script's category.

#### Scenario: Reassign from context menu
- **WHEN** the user long-presses a row and picks a category under "Move to Category"
- **THEN** the script moves immediately and the badge updates

#### Scenario: Create category from editor
- **WHEN** the user taps "New Category…" in the editor's category menu and enters a name
- **THEN** the category is created and immediately assigned to the open script

### Requirement: Studio script selector grouping
The Studio's script selector menu SHALL group scripts under category sections (in category creation order) with an uncategorized trailing section, preserving the freestyle option at top.

#### Scenario: Selector shows grouped scripts
- **WHEN** the user opens the Studio script selector with categorized scripts
- **THEN** scripts list under category section headers matching the library's grouping

### Requirement: Library sort control
The Scripts tab SHALL offer a toolbar sort menu with Last Updated / Date Created / Title (case-insensitive), persisted across launches via `@AppStorage`.

#### Scenario: Sort persists
- **WHEN** the user picks "Title" and relaunches
- **THEN** the library remains sorted by title until changed
