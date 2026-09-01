## ADDED Requirements

### Requirement: External and Bluetooth microphone routing
The system SHALL automatically route audio to connected AirPods or wireless lapel mics (e.g., Rode, DJI) using `AVAudioSession` category `.playAndRecord` + mode `.videoRecording` with `.allowBluetooth` / `.allowBluetoothA2DP`, and reflect the active input in UI.

#### Scenario: Bluetooth mic auto-routes
- **WHEN** AirPods are connected and user enters the studio
- **THEN** `AVAudioSession` routes capture to the Bluetooth input and the UI indicates "AirPods" as the active mic

#### Scenario: Route change updates live
- **WHEN** user connects or disconnects a lapel mic during preview
- **THEN** the system observes `AVAudioSession.routeChangeNotification` and updates the displayed input and VU meter without requiring restart

#### Scenario: Wired headset fallback
- **WHEN** a wired headset or external mic is connected
- **THEN** the system routes to that input and it takes precedence over Bluetooth per `AVAudioSession` priority

### Requirement: Live dBFS VU metering
The system SHALL display live audio levels in dBFS via a VU meter sourced from `AVCaptureAudioDataOutput` or `AVAudioRecorder` metering, updated at least at 10 Hz.

#### Scenario: VU meter reflects speaking volume
- **WHEN** user speaks while in the studio preview
- **THEN** the VU meter animates proportionally to input level (quiet = low, loud = high) and clips indicator shows when exceeding -0 dBFS

#### Scenario: Silence shows floor level
- **WHEN** no audio is present
- **THEN** the meter rests at its minimum (e.g., -60 dBFS or -∞) without jitter

### Requirement: Persistent preferences via AppStorage
The system SHALL store camera defaults (resolution, frame rate, mirror mode, countdown length, and optionally HDR/aspect/LUT preference) in `@AppStorage` (UserDefaults) so they persist across launches.

#### Scenario: Preference persists after relaunch
- **WHEN** user sets resolution to 4K, frame rate to 60 fps, mirror to ON, and countdown to 3 s, then force-quits and relaunches
- **THEN** the studio opens with those exact defaults pre-selected

#### Scenario: Default values on first launch
- **WHEN** app is launched for the first time with no stored preferences
- **THEN** defaults are 1080p, 30 fps, mirror ON (front camera), countdown 3 s, 16:9

### Requirement: Siri Shortcuts and Action Button via AppIntents
The system SHALL expose Siri and iPhone Action Button support via `AppIntents`, allowing "Hey Siri, record a script in OneTake" and Shortcuts/Action Button mapping without custom URL schemes.

#### Scenario: Siri shortcut records a script
- **WHEN** user says "Hey Siri, record a script in OneTake" (or invokes the provided App Shortcut)
- **THEN** the system handles `RecordScriptIntent`, opens the app to the script library or directly to the studio with the most recent (or user-specified) script

#### Scenario: Action Button triggers OneTake
- **WHEN** user maps the iPhone Action Button to the OneTake App Shortcut via Settings → Action Button
- **THEN** pressing the Action Button launches OneTake's record flow as defined by `AppShortcutsProvider`

#### Scenario: Shortcuts app shows OneTake actions
- **WHEN** user opens the Shortcuts app
- **THEN** OneTake's intents (e.g., "Record Script", "Open Script") appear as available actions with parameters (script title/ID)

#### Scenario: Intent handles missing script gracefully
- **WHEN** the Siri intent specifies a script ID that no longer exists
- **THEN** the system falls back to the library view and indicates the script was not found instead of crashing
