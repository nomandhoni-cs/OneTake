## ADDED Requirements

### Requirement: Hardware capture session with resolution and frame rate selection
The system SHALL provide a front-camera `AVCaptureSession` supporting exact resolution selection of 1080p FHD (1920×1080) and 4K UHD (3840×2160) at 24 fps (Film), 30 fps (Standard), and 60 fps (Smooth), configured via `AVCaptureDevice.Format` and `activeVideoMin/MaxFrameDuration`.

#### Scenario: User selects 1080p 30 fps
- **WHEN** user selects 1080p at 30 fps in settings or studio
- **THEN** the capture session configures the front wide-angle device to a format supporting 1920×1080 at 30 fps and preview reflects the selection

#### Scenario: User selects 4K 60 fps on capable device
- **WHEN** user selects 4K at 60 fps on a device whose front camera supports it
- **THEN** the session configures 3840×2160 at 60 fps; if unsupported, the system disables the option and shows an explanatory message

#### Scenario: Session starts with authorization
- **WHEN** user grants camera and microphone permission and enters the studio
- **THEN** the session starts running on a dedicated queue and shows live preview without blocking the main thread

#### Scenario: Graceful handling of denied permission
- **WHEN** camera or microphone permission is denied
- **THEN** the studio shows a `ContentUnavailableView` with a button linking to Settings and does not crash

### Requirement: Native HDR and Dolby Vision support
The system SHALL enable native HDR / Dolby Vision capture where the device supports `isVideoHDREnabled`.

#### Scenario: HDR toggle on supported device
- **WHEN** the front camera supports HDR and user enables HDR
- **THEN** the session enables `isVideoHDREnabled` and records HDR video; on unsupported devices the toggle is hidden or disabled

#### Scenario: HDR fallback
- **WHEN** HDR is requested but the selected format does not support it
- **THEN** the system falls back to SDR and indicates HDR is unavailable for that format

### Requirement: Auto-lock exposure, white balance, and focus on record
The system SHALL freeze Auto-Exposure (AE), Auto White Balance (AWB), and Auto-Focus (AF) the millisecond recording starts via `AVCaptureDevice.lockForConfiguration()`.

#### Scenario: Lock on record start
- **WHEN** user taps Record
- **THEN** the system locks `exposureMode = .locked`, `whiteBalanceMode = .locked`, `focusMode = .locked` before `startRecording()` commits

#### Scenario: Unlock on record stop
- **WHEN** user stops recording
- **THEN** the system restores `exposureMode = .continuousAutoExposure`, `whiteBalanceMode = .continuousAutoWhiteBalance`, `focusMode = .continuousAutoFocus` (or device defaults)

### Requirement: Mirrored preview and session lifecycle
The system SHALL support mirrored front-camera preview toggling and correctly handle session lifecycle across interruptions and backgrounding.

#### Scenario: Mirror toggle
- **WHEN** user toggles Mirror Preview
- **THEN** `AVCaptureVideoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring` or manual mirroring updates immediately and the saved file respects the mirror preference

#### Scenario: Interruption pauses session
- **WHEN** a phone call or `AVAudioSession` interruption occurs during preview or recording
- **THEN** the system observes `AVCaptureSession.wasInterruptedNotification`, pauses UI, and resumes or stops gracefully when interruption ends

#### Scenario: Backgrounding stops recording safely
- **WHEN** user backgrounds the app while recording
- **THEN** the system stops recording, finalizes the file, and does not leave a corrupted MP4
