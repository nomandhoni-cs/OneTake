## ADDED Requirements

### Requirement: Optional script overlay in reaction mode

The system SHALL render the lens-anchored `.ultraThinMaterial` frosted prompter over the reaction composite with an optional script picker that defaults to "No script — Freestyle", reusing the existing selector semantics (`@AppStorage("lastScriptID")` persistence, deleted-script fallback, instant text swap without restarting capture). The prompter SHALL be collapsible: freestyle defaults to a slim "Notes (optional)" pill instead of the full prompter, picking a script expands it automatically, and a hide control collapses it on demand. Pause SHALL freeze reaction prompter scroll exactly as in teleprompter mode, and freestyle recordings SHALL produce takes with no script-bound `scriptID`.

#### Scenario: Reaction with script notes

- **WHEN** the user picks a script in Reaction mode and records
- **THEN** the frosted prompter scrolls reaction notes above the background video while the cutout and background record underneath

#### Scenario: Freestyle reaction default

- **WHEN** the user opens Reaction mode with no script selected
- **THEN** the notes area stays collapsed as a slim "Notes (optional)" pill (expandable on demand) and recording produces a take with nil `scriptID`

#### Scenario: Notes collapse to save space

- **WHEN** the user has no script selected (or taps Hide notes)
- **THEN** only the slim notes pill is shown instead of the full prompter, and picking a script expands it automatically

#### Scenario: Pause freezes reaction scroll

- **WHEN** the user pauses a reaction recording while notes scroll
- **THEN** the prompter offset freezes and resumes from the same position on resume
