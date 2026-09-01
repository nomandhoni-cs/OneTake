# app-navigation Specification

## Purpose
Bottom tab shell with per-tab `NavigationStack` routing, state restoration, and accessibility for the bottom-nav studio flow. Note: The canonical tab shell structure is now defined in `unified-tab-navigation` (4-tab `TabView(sidebarAdaptable)` Liquid Glass with Studio as a first-class inline tab), which supersedes the 3-tab + centered Studio CTA `fullScreenCover` presentation described in this spec's shell requirement. This spec is retained for the additive per-tab navigation, routing, and accessibility requirements that remain valid and are not duplicated in `unified-tab-navigation` (e.g., My Takes → Review push, deep-link handling details, 44pt Studio CTA semantics).

## Requirements
### Requirement: Bottom tab shell with My Takes, Scripts, Profile and centered Studio CTA
The system SHALL render a persistent bottom tab shell with three tabs — My Takes, Scripts, Profile — and a centered, elevated Studio CTA button that presents the camera full-screen; the tab bar SHALL be visible on every tab root and SHALL not be shown inside the full-screen Studio.

*Note: Superseded for shell presentation by `unified-tab-navigation`'s 4-tab inline Studio. The current implementation SHALL use the unified 4-tab shell; this requirement is retained as historical reference and for its scenarios that validate per-tab visibility semantics, adapted to the unified shell where Studio appears inline rather than as a cover.*

#### Scenario: App launches to default tab
- **WHEN** the user cold-launches the app
- **THEN** the system shows the My Takes tab selected with its navigation stack at root and the bottom bar visible with Scripts, Studio CTA, and Profile

#### Scenario: Switching tabs preserves stack
- **WHEN** the user navigates inside Scripts (e.g., opens editor), switches to My Takes, then back to Scripts
- **THEN** the Scripts stack remains at the editor depth and its search text and sheet state are restored

#### Scenario: Studio CTA presents camera
- **WHEN** the user taps the centered Studio button from any tab
- **THEN** the system presents `StudioView` as a `.fullScreenCover` over the tab shell, initializing the camera session

#### Scenario: Studio dismiss returns to previous tab
- **WHEN** the user dismisses Studio (close/X or swipe where allowed)
- **THEN** the system dismisses the cover, stops the capture session, and returns to the tab that presented it with that tab’s stack intact

### Requirement: Per-tab NavigationStack and routing
The system SHALL maintain an independent `NavigationStack` per tab (My Takes, Scripts, Profile) using a shared `Route` enum; deep links (e.g., “Record with Prompter” from Scripts editor) SHALL target the Studio cover rather than pushing onto a tab stack.

*Note: In the unified 4-tab implementation, deep links target selecting the Studio tab (see `unified-tab-navigation` Studio deep-link routing) rather than a cover. Both routing mechanisms SHALL converge on showing Studio with the requested script via `lastScriptID`/`initialScriptID`.*

#### Scenario: Record with Prompter from Scripts
- **WHEN** the user taps “Record with Prompter” in the Scripts editor sheet
- **THEN** the system dismisses the sheet and presents Studio with that script pre-selected via `lastScriptID`

#### Scenario: My Takes to Review navigation
- **WHEN** the user taps a take in My Takes
- **THEN** the system pushes `ReviewView` onto the My Takes stack and the back button returns to My Takes

### Requirement: State restoration and accessibility
The system SHALL persist the selected tab via `SceneStorage`/`AppStorage` and expose VoiceOver labels for each tab and the Studio CTA (44pt hit target, `accessibilityLabel` and `accessibilityHint`).

#### Scenario: Tab selection persists across background
- **WHEN** the user backgrounds and foregrounds the app
- **THEN** the previously selected tab remains selected

#### Scenario: VoiceOver tab navigation
- **WHEN** VoiceOver is enabled
- **THEN** each tab item and the Studio button are focusable with correct labels (“My Takes”, “Scripts”, “Record, opens camera”, “Profile”)
