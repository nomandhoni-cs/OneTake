## ADDED Requirements

### Requirement: Versioned first-run decision flow
The system SHALL show onboarding when `completedOnboardingVersion` is below the
current version (2), as a sequence of decision steps — Welcome (value props,
Continue), Terms (blocking accept), Trial offer (skippable), Permissions
explainer (no system prompts) — then the tab shell. No step SHALL be a
tutorial carousel; each step SHALL have a primary action and, where legal, a
skip path. No system permission prompt SHALL fire from any onboarding step.

#### Scenario: Fresh install walks decisions then shell
- **WHEN** the app launches with no onboarding record
- **THEN** Welcome → Terms (must Agree) → Trial offer (may skip) → Permissions
  explainer → tab shell, and relaunch goes straight to the shell

#### Scenario: Legal bump forces terms-only pass
- **WHEN** the accepted legal version is below current with onboarding complete
- **THEN** launch shows only the Terms step; agreeing returns to the shell

### Requirement: Permissions explained, asked in context
Onboarding SHALL explain why camera, microphone, and Photos-add matter with
one line each, and SHALL state prompts appear at first record/save. Camera/mic
requests SHALL fire only from Studio, Photos-add only from save, each with the
existing denied → Settings recovery.

#### Scenario: Explainer promises, Studio delivers
- **WHEN** the user finishes the explainer and taps Record in Studio
- **THEN** the camera/mic system prompt appears there (or the denied alert
  with Open Settings if previously denied)
