# live-recording-hud Specification

## Purpose
TBD - created by archiving change modern-apple-api-features. Update Purpose after archive.
## Requirements
### Requirement: Dynamic Island and Live Activity recording HUD
The system SHALL render active recording time (🔴 REC `mm:ss`) and audio levels inside the Dynamic Island and on the iOS Lock Screen via `ActivityKit` `ActivityAttributes`, starting on record and ending on stop.

#### Scenario: Live Activity starts on record
- **WHEN** user taps Record and capture begins
- **THEN** a Live Activity starts via `Activity.request(attributes:content:)` showing elapsed time at 00:00 and current audio level

#### Scenario: Timer updates each second
- **WHEN** recording has been active for 14 seconds
- **THEN** the Dynamic Island compact view and Lock Screen show "🔴 REC 00:14" and the level meter reflects current dBFS

#### Scenario: Dynamic Island styles
- **WHEN** recording is active on a Dynamic Island device
- **THEN** the compact leading/trailing and expanded views render correctly (timer + level), and on non-Dynamic Island devices only the Lock Screen banner appears

#### Scenario: Live Activity ends on stop
- **WHEN** user stops recording
- **THEN** the Live Activity ends within 2 seconds and is removed from the Lock Screen/Dynamic Island

#### Scenario: Live Activities disabled fallback
- **WHEN** `ActivityAuthorizationInfo.areActivitiesEnabled == false` or user denied Live Activities
- **THEN** recording still succeeds and an in-app HUD shows REC timer and levels without crashing

#### Scenario: Multiple activities not leaked
- **WHEN** user records, stops, and records again
- **THEN** only one Live Activity exists at a time; previous activity is ended before a new one starts

### Requirement: Tactile 3-second countdown with CoreHaptics
The system SHALL provide a 3-second countdown before recording using `CoreHaptics` `CHHapticEngine`: transient taps for counts 3 and 2, and an intense continuous burst when recording begins, with fallback to `UIFeedbackGenerator` where unavailable.

#### Scenario: Countdown haptic sequence
- **WHEN** user initiates recording with countdown enabled
- **THEN** the system plays a light transient tap at "3", a second at "2", and a sustained intense burst at "1/GO" synchronized with the visual countdown

#### Scenario: Countdown can be skipped or configured
- **WHEN** user disables countdown in settings
- **THEN** recording starts immediately with only the GO burst (or no haptics if disabled)

#### Scenario: CoreHaptics unavailable fallback
- **WHEN** device does not support `CHHapticEngine` (`supportsHaptics == false`)
- **THEN** the system falls back to `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` producing perceptible taps and a heavier notification on GO

#### Scenario: Haptic engine resilience
- **WHEN** `CHHapticEngine` stops due to audio session interruption or backgrounding
- **THEN** the engine's `resetHandler` restarts it automatically and subsequent haptics succeed without user action

#### Scenario: Countdown respects silent switch (configurable)
- **WHEN** countdown is active
- **THEN** haptics fire regardless of mute switch (haptics are not audio), and any audible tick is optional and respects the mute setting if implemented

