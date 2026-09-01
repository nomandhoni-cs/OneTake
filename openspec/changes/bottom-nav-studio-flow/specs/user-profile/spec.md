## ADDED Requirements

### Requirement: Profile tab
The system SHALL display a Profile tab as a grouped inset list with sections: Preferences (links to camera defaults, countdown, aspect/LUT), Takes summary (count of takes, total duration), About (app version/build, privacy), and placeholder rows for future account features; the tab SHALL be reachable from the bottom bar and SHALL push detail views onto the Profile stack.

#### Scenario: Profile lists expected sections
- **WHEN** the user opens the Profile tab
- **THEN** the list shows Preferences, Takes summary, and About sections with correct row titles and chevrons where applicable

#### Scenario: Preferences rows navigate
- **WHEN** the user taps a Preferences row (e.g., “Camera defaults”)
- **THEN** the system pushes the corresponding settings detail (reusing `StudioSettingsSheet` content or a dedicated form) onto the Profile stack

#### Scenario: Takes summary reflects store
- **WHEN** there are 7 takes totaling 4:32
- **THEN** the Takes summary row shows “7 takes · 4:32” derived live from `@Query` Takes

### Requirement: Profile empty and navigation state
The system SHALL maintain Profile’s `NavigationStack` state independently of other tabs and SHALL show `ContentUnavailableView` only if a pushed detail has no content (not at root).

#### Scenario: Profile stack retention
- **WHEN** the user pushes a detail in Profile, switches tabs, then returns
- **THEN** the Profile stack remains at that detail depth
