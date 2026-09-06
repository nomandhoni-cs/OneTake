## ADDED Requirements

### Requirement: Blocking legal acceptance
The system SHALL require explicit Terms & Privacy acceptance (Agree action
recording an ISO-8601 timestamp and legal version) before first use. The
screen SHALL render the bundled documents and link upstream URLs when
configured. Acceptance SHALL be re-accessible read-only from Profile.

#### Scenario: Cannot skip terms
- **WHEN** the user reaches the Terms step
- **THEN** no Skip/Not-now path exists; only Agree advances (Back allowed)

#### Scenario: Terms re-readable later
- **WHEN** the user opens Profile → Terms & Privacy
- **THEN** the same documents render read-only with upstream links, no Agree button
