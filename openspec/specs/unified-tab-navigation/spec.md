# unified-tab-navigation Specification

## Purpose
Unified 4-tab navigation shell that presents My Takes, Scripts, Studio, and Profile as first-class tabs inside a single native `TabView(sidebarAdaptable)` Liquid Glass container. Studio is discoverable without an external overlay, with per-tab `NavigationPath` stacks, `@SceneStorage` persistence, and deep-link routing via `Notification.Name.showStudio`.

## Requirements
### Requirement: Unified 4-tab navigation shell
The system SHALL present a single native `TabView` with four tabs — My Takes, Scripts, Studio, Profile — inside the same `sidebarAdaptable` Liquid Glass container, where Studio is a first-class tab (not an external overlay) with per-tab `NavigationPath` state and selection persisted via `@SceneStorage`.

#### Scenario: Four tabs visible in switcher
- **WHEN** the app launches on iPhone
- **THEN** the bottom bar shows four tabs in order My Takes (film.stack), Scripts (doc.text), Studio (video.fill), Profile (person.crop.circle) with Studio discoverable without an external floating button

#### Scenario: Tab selection persists per launch
- **WHEN** the user selects the Studio tab and relaunches the app
- **THEN** the Studio tab remains selected via `@SceneStorage` restoration

#### Scenario: Per-tab navigation stacks are independent
- **WHEN** the user pushes a detail in Scripts, switches to My Takes, then returns to Scripts
- **THEN** the Scripts stack state is preserved and not reset

#### Scenario: Studio no longer presents as sheet
- **WHEN** the user taps Studio
- **THEN** the camera appears inline as tab content, not via `fullScreenCover` or detached overlay

### Requirement: Studio deep-link routing
The system SHALL route legacy `showStudio` triggers (notification `Notification.Name.showStudio` and editor "Record with Prompter") to selecting the Studio tab and optionally pushing the initial script via the Studio tab's `NavigationPath`, preserving the `lastScriptID` selection.

#### Scenario: Notification selects Studio tab
- **WHEN** `NotificationCenter` posts `.showStudio`
- **THEN** `selectedTab` becomes `.studio` and the Studio camera becomes visible

#### Scenario: Editor launch pre-selects script in Studio tab
- **WHEN** the user taps "Record with Prompter" for script `S` while on Scripts
- **THEN** the app selects the Studio tab and the prompter loads `S` as `initialScriptID`

### Requirement: Accessibility and HIG tab bar
The system SHALL expose 44pt hit targets for each tab, VoiceOver labels/hints in order My Takes → Scripts → Studio → Profile, and `sidebarAdaptable` overflow handling on compact devices.

#### Scenario: VoiceOver order
- **WHEN** VoiceOver focus moves across the tab bar
- **THEN** the order is My Takes, Scripts, Studio, Profile with correct `accessibilityLabel` and `accessibilityHint` for Studio ("Opens camera")

#### Scenario: Compact overflow
- **WHEN** the bar renders on iPhone SE/mini
- **THEN** titles remain legible and the bar does not clip; `sidebarAdaptable` collapses gracefully
