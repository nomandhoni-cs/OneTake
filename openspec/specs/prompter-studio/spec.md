# prompter-studio Specification

## Purpose
TBD - created by archiving change modern-apple-api-features. Update Purpose after archive.
## Requirements
### Requirement: ProMotion 120 Hz smooth scrolling
The system SHALL drive prompter text scrolling locked to the display refresh rate using `TimelineView(.animation)` (primary) with `CADisplayLink` fallback, achieving 120 Hz on ProMotion devices and eliminating frame drops. Scrolling SHALL freeze instantly when recording is paused and resume from the same offset on resume; while paused, changing speed SHALL not advance the offset.

#### Scenario: Prompter scrolls at 120 Hz on capable device
- **WHEN** recording is active and prompter is scrolling at 2.0× speed on an iPhone with ProMotion
- **THEN** text translation updates at the display's native refresh rate (up to 120 Hz) as measured by Instruments, with no visible stutter

#### Scenario: Low-power mode throttling
- **WHEN** device is in Low Power Mode and caps refresh to 60 Hz
- **THEN** the prompter continues scrolling smoothly at 60 Hz without requiring user action

#### Scenario: CADisplayLink fallback
- **WHEN** `TimelineView` cadence is throttled under load
- **THEN** the system falls back to `CADisplayLink` to maintain display-linked updates

#### Scenario: Pause freezes scroll
- **WHEN** the user pauses recording while the prompter is scrolling
- **THEN** the prompter offset stops changing and remains at the current position until resume

### Requirement: Lens-anchored floating prompter
The system SHALL render the prompter as a native `.ultraThinMaterial` frosted glass box pinned directly beneath the Dynamic Island or notch, including an eye-line accent guide to anchor gaze near the lens.

#### Scenario: Prompter anchored below Dynamic Island
- **WHEN** studio is presented on a device with Dynamic Island
- **THEN** the prompter's top edge is pinned below the Dynamic Island safe area with consistent padding and the eye-line guide (thin stroke) visible

#### Scenario: Prompter on notched device
- **WHEN** studio is presented on a notched device without Dynamic Island
- **THEN** the prompter is pinned below the notch safe area with identical material and guide treatment

### Requirement: Live in-camera tweak tray with dual controls
The system SHALL provide tweak controls for speed, font size, and backdrop opacity with BOTH continuous `Slider` and discrete `[−]/[+]` stepper buttons sharing a single source of truth, and for aspect ratio masking. Controls SHALL be presented exclusively in the Studio settings bottom sheet (not inline) with `detents: [.medium, .large]` and a drag indicator; changes SHALL apply live during preview and recording without restarting the `AVCaptureSession` or resetting scroll position, except format controls disabled while recording/paused per capture-engine. The tray’s state SHALL be backed by `AppStorage`/shared `Observable` so sheet dismiss does not lose values; the Live Preview LUT is not shown live (export-only per design).

#### Scenario: Speed slider and steppers stay in sync
- **WHEN** user drags the speed slider from 1.0× to 2.5× and then taps the [+] stepper
- **THEN** the speed increments to 2.6× (step 0.1) and the slider thumb reflects 2.6× with haptic feedback

#### Scenario: Font scaling dual controls
- **WHEN** user adjusts font size via slider (18 pt–36 pt) or stepper (step 1 pt)
- **THEN** prompter text re-renders at the new point size immediately without restarting the scroll

#### Scenario: Backdrop opacity control
- **WHEN** user adjusts backdrop opacity from 0% (transparent) to 80% (dark frosted)
- **THEN** the material's opacity updates live and persists for the session

#### Scenario: Tweak tray is live during recording
- **WHEN** user adjusts any tweak while recording is in progress
- **THEN** changes apply instantly without stopping capture or resetting scroll position

#### Scenario: Sheet presents tweak controls
- **WHEN** the user taps the settings gear in Studio
- **THEN** the bottom sheet presents with speed/font/opacity/aspect controls grouped, with stepper buttons and sliders sharing state, and does not interrupt the running preview

### Requirement: Dynamic aspect ratio masking
The system SHALL provide live animated letterbox/pillarbox masks for 9:16 (Reels/Shorts), 16:9 (YouTube), and 1:1 (Square) that animate transitions without stopping preview.

#### Scenario: Switch aspect ratio during preview
- **WHEN** user selects 9:16 while in 16:9 preview
- **THEN** the preview animates pillarbox/letterbox masks to 9:16 with a smooth transition and recording respects the new frame

#### Scenario: All three ratios available
- **WHEN** user opens the aspect ratio picker
- **THEN** options for 9:16, 16:9, and 1:1 are present and selectable

#### Scenario: Mask does not affect capture file incorrectly
- **WHEN** user records at 9:16 and exports
- **THEN** the saved file's dimensions or crop reflect 9:16 as indicated by the mask (either via crop metadata or post-process, as specified)
