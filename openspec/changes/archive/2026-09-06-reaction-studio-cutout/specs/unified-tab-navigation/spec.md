## MODIFIED Requirements

### Requirement: Unified 4-tab navigation shell

The system SHALL present a single native `TabView` with four tabs — My Takes, Scripts, Studio, Profile — inside the same `sidebarAdaptable` Liquid Glass container, where the Studio tab presents a 2-card mode picker (Teleprompter / Reaction) and each mode opens full-screen via `fullScreenCover` (tab bar hidden), dismissing back to the picker, with per-tab `NavigationPath` state and selection persisted via `@SceneStorage`.

#### Scenario: Four tabs visible in switcher

- **WHEN** the app launches on iPhone
- **THEN** the bottom bar shows four tabs in order My Takes (film.stack), Scripts (doc.text), Studio (video.fill), Profile (person.crop.circle) with Studio discoverable without an external floating button

#### Scenario: Tab selection persists per launch

- **WHEN** the user selects the Studio tab and relaunches the app
- **THEN** the Studio tab remains selected via `@SceneStorage` restoration

#### Scenario: Per-tab navigation stacks are independent

- **WHEN** the user pushes a detail in Scripts, switches to My Takes, then returns to Scripts
- **THEN** the Scripts stack state is preserved and not reset

#### Scenario: Studio modes present full-screen over picker

- **WHEN** the user taps a Studio mode card (Teleprompter or Reaction)
- **THEN** the camera interface covers the full screen with the tab bar hidden, and dismissing returns to the mode picker with `studioPath` state preserved

## ADDED Requirements

### Requirement: Studio mode picker cards

The system SHALL render two mode cards in the Studio tab — Teleprompter (existing camera + script flow) and Reaction (new cutout flow) — each with a 44pt-accessible target, VoiceOver label/hint, and a thumbnail glyph, where selecting a card opens that mode full-screen.

#### Scenario: Picker shows two modes

- **WHEN** the user taps the Studio tab
- **THEN** two cards appear: "Teleprompter" (video.fill) and "Reaction" (person.crop.rectangle.stack), each activatable by tap and VoiceOver

#### Scenario: Deep link preserves mode routing

- **WHEN** `NotificationCenter` posts `.showStudio` while no recording is active
- **THEN** `selectedTab` becomes `.studio` and the picker (or a pre-selected mode from the editor's "Record" action) appears; while a mode is recording, the request is a no-op so the session continues uninterrupted and the tab-switch guard stays armed
