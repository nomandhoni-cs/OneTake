## ADDED Requirements

### Requirement: First frame is usable content
The system SHALL render the 4-tab shell on every launch, including the first,
with no intervening carousel, splash, gate, or forced step. Teaching happens
through empty states with actions, never through blocking instruction.

#### Scenario: Fresh install lands in tabs
- **WHEN** the app launches with no prior state
- **THEN** the Studio tab bar item is visible within 5s and no Skip/Continue/
  Next/Get Started control exists anywhere in the hierarchy

#### Scenario: Empty library teaches action
- **WHEN** the Scripts tab opens with zero scripts
- **THEN** a "No Scripts Yet" empty state with a "Create First Script" action
  is shown; the Takes tab likewise offers "Record your first take"

### Requirement: Permissions ask in context
The system SHALL request camera/microphone only when Studio opens (where the
preview makes the value visible) and Photos-add only at save time. A denied
permission SHALL surface a human explanation with an Open Settings path and
SHALL never loop or block launch or the library.

#### Scenario: Denied camera offers recovery
- **WHEN** camera access is denied and Studio opens
- **THEN** a "Camera & Microphone Required" alert offers Open Settings and
  Cancel, and the library remains fully usable

#### Scenario: Photos denied explains at save
- **WHEN** Photos-add is denied at save time
- **THEN** the error names the cause and the fix ("Enable in Settings →
  Privacy → Photos") and no raw system string is shown

### Requirement: No placeholder account UI
The system SHALL NOT ship placeholder account/sign-in rows. Account UI
appears only with the change that implements authentication.

#### Scenario: Profile shows no account placeholder
- **WHEN** the user opens the Profile tab
- **THEN** no "Sign in" or "coming soon" row exists; About shows version/build plus the Privacy Settings link
