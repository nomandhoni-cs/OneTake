## Why

OneTake currently ships as the default SwiftData template (`Item.timestamp` list) with no domain features. The product vision requires a fully native iOS teleprompter + capture studio built exclusively on first-party Apple frameworks (SwiftUI, SwiftData, AVFoundation, CoreImage/Metal, ActivityKit, CoreHaptics, AVAudioSession, AppIntents) with zero third-party dependencies. Without this change the app cannot deliver instant offline script persistence, hardware-accelerated capture/trim/color, ProMotion scrolling, or system-integrated recording UX that differentiates it from Electron/web-wrapped competitors. Building now establishes the correct architecture (Observation, SwiftData schema, AVFoundation pipeline) before any legacy code accumulates.

## What Changes

- Replace template `Item` model with OneTake domain SwiftData schema: `Script`, `Draft`, and recording metadata (`Take`) persisted via `@Model` / `@Query` with instant autosave and no loading spinners.
- Add Script Workspace: `NavigationStack` + `.insetGrouped` lists, `.searchable()` filtering, `.swipeActions` (duplicate/delete), `ContentUnavailableView` empty state, and a distraction-free editor sheet with live word-count telemetry and 1-tap **Record with Prompter** action.
- Add Live Word & Cadence Engine: `@Observable` view model computing `duration = words / 130 wpm` in real time as the user types.
- Implement OneTake Recording Studio on `AVCaptureSession`: front-camera 1080p FHD / 4K UHD at 24/30/60 fps, HDR/Dolby Vision, `lockForConfiguration()` to freeze AE/AWB/AF on record, and mirrored preview toggle.
- Implement ProMotion 120 Hz prompter: `TimelineView(.animation)` (fallback `CADisplayLink`) driving lens-anchored `.ultraThinMaterial` frosted glass box beneath Dynamic Island/notch with eye-line guide.
- Add Live In-Camera Tweak Tray: continuous `Slider` (1.0x–4.0x speed, 18–36 pt font, 0–80% opacity) + discrete `[−]/[+]` steppers, plus animated letterbox/pillarbox masks for 9:16 / 16:9 / 1:1.
- Integrate Dynamic Island & Live Activity via `ActivityKit`: `ActivityAttributes` rendering 🔴 REC timer + audio levels on Dynamic Island and Lock Screen; end activity on stop.
- Add Tactile 3-Second Countdown via `CoreHaptics` (`CHHapticEngine`): transient taps on 3/2, sustained burst on GO with graceful fallback to `UINotificationFeedbackGenerator` when hardware unsupported.
- Add Review, Trim & GPU Color Export Studio: instant `AVKit.VideoPlayer` preview, dual-handle `CMTimeRange` scrubber with `AVAssetExportSession` `.passthrough` stream trim (<1 s, no re-encode), `CoreImage.CIFilter.colorCube` + Metal 3D LUT grading (4 presets: Natural, Warm Studio, Cinematic Contrast, Clean Monochrome), `PHPhotoLibrary` save with sandbox cleanup, and `ShareLink` sheet.
- Add Hardware & System Extensions: `AVAudioSession(.videoRecording)` routing to AirPods/wireless mics (Rode/DJI) with dBFS VU metering, `@AppStorage` defaults (resolution, fps, mirror, countdown), and `AppIntents` for Siri ("Hey Siri, record a script in OneTake") + iPhone Action Button.
- Extend `OneTakeApp` `ModelContainer` schema, add `Info.plist` privacy keys (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`), `NSSupportsLiveActivities`, and `com.apple.developer.activitykit` entitlement.

## Capabilities

### New Capabilities

- `script-workspace`: SwiftData script/draft library, `NavigationStack` + `.insetGrouped` lists, `.searchable()` filtering, `.swipeActions` duplicate/delete, `ContentUnavailableView`, and distraction-free editor sheet.
- `cadence-engine`: Live word count and estimated duration via `@Observable` at 130 wpm baseline, toolbar telemetry.
- `capture-engine`: `AVCaptureSession` hardware pipeline — 1080p/4K @ 24/30/60 fps, HDR/Dolby Vision, `AVCaptureDevice.lockForConfiguration()` AE/AWB/AF freeze, preview mirroring and session lifecycle.
- `prompter-studio`: ProMotion 120 Hz scrolling (`TimelineView`/`CADisplayLink`), lens-anchored `.ultraThinMaterial` prompter, tweak tray (speed/font/opacity sliders + steppers), dynamic aspect-ratio masking (9:16, 16:9, 1:1).
- `live-recording-hud`: `ActivityKit` Live Activity + Dynamic Island HUD (REC timer, audio levels) and `CoreHaptics` 3-second countdown haptics.
- `trim-color-export`: `AVKit` instant preview, `AVAssetExportSession` + `CMTimeRange` sub-second trimming, `CoreImage`/`Metal` `CIFilter.colorCube` 3D LUT grading (4 presets), `PHPhotoLibrary` save + cache cleanup, `ShareLink`.
- `audio-settings-intents`: `AVAudioSession` Bluetooth/external mic routing + dBFS metering, `@AppStorage` persistent preferences, `AppIntents` Siri Shortcuts & Action Button.

### Modified Capabilities

- None — greenfield implementation; existing `Item` model is replaced (no existing capabilities to delta).

## Impact

- **Code**: Replaces `ContentView.swift`/`Item.swift` template; adds ~15–20 new Swift files under `OneTake/Features/{Workspace,Studio,Review,Settings}` + `Core/` (SwiftData, Haptics, Activity, Audio). Extends `OneTakeApp.swift` container setup.
- **APIs/Entitlements**: New `ActivityKit` Live Activity, `CoreHaptics`, `AVFoundation`, `CoreImage/Metal`, `Photos`, `AppIntents`; requires `Info.plist` camera/mic strings, background modes if needed, Live Activities capability.
- **Dependencies**: Zero third-party dependencies; adds only Apple frameworks. Minimum deployment likely iOS 17+ (Observation, SwiftData, ActivityKit modern APIs).
- **UX**: Entire app navigation changes from `NavigationSplitView` Item list to `NavigationStack` script library → editor → studio → review flow.
- **Performance/Risk**: Real-time video pipeline and Metal shader work must be tested on device; simulator cannot validate `AVCaptureSession`, `CHHapticEngine`, or `ActivityKit` end-to-end.
- **Data**: Lightweight SwiftData migration — template data is ephemeral; no user migration path required.
