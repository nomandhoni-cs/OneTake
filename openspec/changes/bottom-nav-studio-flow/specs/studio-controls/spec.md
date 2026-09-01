## ADDED Requirements

### Requirement: In-camera script selector
The system SHALL render a script selector in the Studio top bar bound to `@Query` scripts; it SHALL list all scripts by title (or “No script — Freestyle” as first option) and changing selection SHALL swap `PrompterView` text instantly without restarting the `AVCaptureSession`; selection SHALL persist to `@AppStorage("lastScriptID")` and restore on next Studio presentation; if the selected script is deleted, the selector SHALL fall back to “No script” and show a transient “Script not available” indicator.

#### Scenario: Switch script while previewing
- **WHEN** the user is in Studio preview and selects a different script from the selector
- **THEN** the prompter text updates to the new script body immediately and the camera preview continues uninterrupted

#### Scenario: No script mode
- **WHEN** the user selects “No script — Freestyle”
- **THEN** the prompter shows placeholder text and recording produces a take with no script-bound `scriptID` (or nil freestyle) and can still be saved

#### Scenario: Deleted script fallback
- **WHEN** the `lastScriptID` points to a deleted script on Studio open
- **THEN** the selector shows “No script” and does not crash

### Requirement: Pause and resume recording
The system SHALL provide Pause/Resume while recording: tapping Pause freezes `AVCaptureMovieFileOutput` (via `pauseRecording`/`resumeRecording` when available, otherwise segment-file fallback), freezes prompter scroll and the REC timer, and sends a single paused-state update to the Live Activity; Resume continues the same logical take, restarts scroll/timer and Live Activity updates, and the final file on Stop SHALL be a single merged MP4 (no orphan segments); while paused the shutter shows Resume/Stop controls and a dimmed preview with “Paused” badge; if paused and the app backgrounds or receives interruption, the system SHALL auto-`stopRecording` to finalize the file safely.

#### Scenario: Pause freezes capture and prompter
- **WHEN** the user taps Pause during recording
- **THEN** the file segment is frozen, prompter stops scrolling, timer stops incrementing, and the Live Activity shows paused state

#### Scenario: Resume continues same take
- **WHEN** the user taps Resume while paused
- **THEN** recording continues to the same take file (merged), prompter resumes, timer resumes, and Live Activity returns to recording state

#### Scenario: Stop after pause produces single file
- **WHEN** the user pauses twice then stops
- **THEN** the resulting `Take.relativeFilePath` points to a single MP4 file containing the concatenated segments and no temporary segment files remain

#### Scenario: Background while paused finalizes
- **WHEN** the app backgrounds while paused
- **THEN** the system finalizes the file, clears `isPaused`, and the take appears in My Takes with the correct duration

### Requirement: Recording controls in camera
The system SHALL show context-appropriate controls: Preview → Record button, Recording → Pause + Stop, Paused → Resume + Stop; the existing Record/Pause/Stop semantics SHALL drive `CaptureService`, timer, `HapticsService`, and `RecordingActivityService` together so they stay in sync.

#### Scenario: Controls sync with state
- **WHEN** the recording state transitions from recording to paused
- **THEN** the central Record button is replaced by Resume and the Stop button remains visible, with haptic feedback on each transition
