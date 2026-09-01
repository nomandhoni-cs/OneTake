## 1. Project Scaffolding & Entitlements

- [x] 1.1 Add `Info.plist` privacy keys `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` and `NSSupportsLiveActivities = YES`; add Live Activities capability entitlement (`com.apple.developer.activitykit`).
- [x] 1.2 Create folder structure `OneTake/Features/{Workspace,Studio,Review,Settings}` + `OneTake/Core/{Persistence,Haptics,Activity,Audio,Export}` and update Xcode project references.
- [x] 1.3 Set minimum deployment to iOS 17.0 (required for `@Observable`, SwiftData, modern `ActivityKit`) and verify `OneTakeApp.swift:13` builds.
- [x] 1.4 Add `.cube` LUT assets (Natural identity, Warm Studio, Cinematic Contrast, Clean Monochrome) as bundled `Data` resources (64×64×64) and verify they load.

## 2. SwiftData Domain Model & Persistence

- [x] 2.1 Replace `Item.swift:11` `@Model` with `Script` (`id: UUID`, `title: String`, `body: String`, `createdAt/updatedAt: Date`, `takes: [Take]`) and `Take` (`id: UUID`, `scriptID: UUID`, `fileURL: URL`, `createdAt: Date`, `duration: TimeInterval`, `trimRange: CMTimeRange?`, `lutPreset: String`); add `SchemaMigrationPlan` if needed.
- [x] 2.2 Update `OneTakeApp.swift:13` `Schema([Script.self, Take.self])` and `ModelConfiguration(isStoredInMemoryOnly: false)`; verify autosave and lightweight migration on device.
- [x] 2.3 Seed logic: on first launch with empty store, do not pre-populate; verify `ContentUnavailableView` path (spec: script-workspace).
- [x] 2.4 Unit test: insert/fetch/delete `Script` via in-memory `ModelContainer`; verify `updatedAt` changes on save.

## 3. Script Workspace & Editor (spec: script-workspace)

- [x] 3.1 Replace `ContentView.swift:11` `NavigationSplitView` with `NavigationStack(path:)` + enum `Route`; root is `ScriptLibraryView` using `.insetGrouped` lists, `ContentUnavailableView` empty state, and `EditButton`.
- [x] 3.2 Implement `ScriptLibraryView` with `@Query` live fetch, row view (title, body preview, timestamp), and `.searchable()` filtering over title/body (case-insensitive) with no-results state.
- [x] 3.3 Add `.swipeActions` on rows: Duplicate (copy title + " copy", new `UUID`) and Delete (with animation, cascade delete takes); verify no orphaned files.
- [x] 3.4 Build distraction-free `ScriptEditorSheet` (native `.sheet`) with `TextEditor` focused on `body`, toolbar showing word count/duration telemetry, and 1-tap "🎥 Record with Prompter" `NavigationLink` pushing `StudioView(script:)`.
- [x] 3.5 UI test: create → search → duplicate → delete flow; snapshot test with `#Preview` for empty, populated, and searching states.

## 4. Cadence Engine (spec: cadence-engine)

- [x] 4.1 Create `@Observable final class CadenceViewModel` computing `wordCount` (split on whitespace, filter empty) and `durationSeconds = ceil(words / 130 * 60)` formatted `m:ss`; debounce only where needed, update synchronously.
- [x] 4.2 Bind `CadenceViewModel` to `ScriptEditorSheet` body via `@Bindable`/`onChange`; verify toolbar updates live while typing with no stale reads.
- [x] 4.3 Unit tests: 0 words → 0:00, 130 words → 1:00, 13 words → 0:06, punctuation/line-break triple-space cases, rapid typing final count.

## 5. Capture Engine — AVFoundation Pipeline (spec: capture-engine)

- [x] 5.1 Implement `actor CaptureService` owning `AVCaptureSession` on `sessionQueue`; configure `AVCaptureDeviceInput` (front wide-angle), `AVCaptureMovieFileOutput`; handle `AVCaptureSession` start/stop, permission preflight, and `wasInterruptedNotification`.
- [x] 5.2 Add resolution/fps picker: enumerate `device.formats` to filter 1080p/4K × 24/30/60; set `activeFormat` + `activeVideoMin/MaxFrameDuration`; disable unsupported combos with explanatory label; add HDR toggle via `isVideoHDREnabled` where supported.
- [x] 5.3 Implement preview layer `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer` (videoGravity `.resizeAspectFill`) with mirror toggle (`automaticallyAdjustsVideoMirroring`); ensure saved file respects mirror preference.
- [x] 5.4 Implement `lockForConfiguration()` freeze on `startRecording()` (`exposureMode .locked`, `whiteBalanceMode .locked`, `focusMode .locked`) and restore to `.continuousAuto` on `stopRecording()`; verify via device logs.
- [x] 5.5 Handle session lifecycle: `AVAudioSession.interruptionNotification`, app `scenePhase` background → finalize file safely; `ContentUnavailableView` when permission denied with Settings deep-link.
- [ ] 5.6 Manual device test matrix: 1080p30, 4K30, 4K60 (where available), HDR on/off, lock verification; Instruments check for main-thread blocking (must be zero).

## 6. Prompter Studio — Scroll, Tray & Masks (spec: prompter-studio)

- [x] 6.1 Build `PrompterView` reading `Script.body`; drive scroll with `TimelineView(.animation(minimumInterval: 1/120))` computing `offsetY += pointsPerSecond * deltaTime` (`pointsPerSecond = base * speedMultiplier` 1.0–4.0×); add `CADisplayLink` fallback when `TimelineView` cadence drops.
- [x] 6.2 Style prompter as `.ultraThinMaterial` rounded rectangle with eye-line accent stroke, pinned via `safeAreaInset(edge: .top)` beneath Dynamic Island/notch; verify on both device types.
- [x] 6.3 Build tweak tray: `Slider` + `Stepper` pairs for speed (1.0–4.0× step 0.1), font (18–36 pt step 1), opacity (0–0.8 step 0.05) sharing single `@Bindable` source; add `UIImpactFeedback` on stepper taps; changes apply live during recording without resetting scroll.
- [x] 6.4 Implement aspect masks: overlay `Color.black` letterbox/pillarbox for 9:16 / 16:9 / 1:1 with `matchedGeometryEffect` animated transitions; ensure selected mask is reflected in export crop/metadata path.
- [ ] 6.5 Performance audit: Instruments Core Animation FPS = 120 Hz on ProMotion, 60 Hz in Low Power Mode; no frame drops at 4.0× speed.

## 7. Live Recording HUD — ActivityKit & CoreHaptics (spec: live-recording-hud)

- [x] 7.1 Define `RecordingAttributes: ActivityAttributes` with `ContentState(elapsedSeconds: Int, audioLevel: Float, isRecording: Bool)`; create `LiveActivity` widget extension with `ActivityConfiguration` for Lock Screen + Dynamic Island compact/expanded views (🔴 REC `mm:ss` + level meter).
- [x] 7.2 Wire `CaptureService` start/stop to `Activity.request` / `activity.update(using:)` (1 Hz throttle, respecting 4 updates/sec limit) / `activity.end`; check `ActivityAuthorizationInfo.areActivitiesEnabled` and fall back to in-app HUD; ensure single activity at a time (end previous before start).
- [x] 7.3 Implement `HapticsService` with lazy `CHHapticEngine`, pre-warm on `StudioView.onAppear`, `resetHandler` restart, capability check `supportsHaptics`; countdown pattern: transient at 3, transient at 2, continuous burst (intensity 1.0, 0.3 s) at GO synchronized to visual countdown.
- [x] 7.4 Add countdown UI (full-screen 3-2-1/GO) with `countdownEnabled` `@AppStorage` toggle; when engine unsupported, fall back to `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`.
- [ ] 7.5 Device tests: Live Activity appears in Dynamic Island + Lock Screen, timer increments each second, ends within 2 s of stop; haptics perceptible on Taptic Engine devices, fallback on SE-class; interruption (call) restarts engine.

## 8. Review, Trim & GPU Color Export (spec: trim-color-export)

- [x] 8.1 Build `ReviewView(take:)` with `AVKit.VideoPlayer(player: AVPlayer(url: take.fileURL))` for zero-delay preview; support scrub seek without re-encode.
- [x] 8.2 Implement dual-handle trim scrubber producing `CMTimeRange(start: trimmedStart, duration: trimmedDuration)` with constraints (start < end, min 1 s, snap to frame); preview loop respects handles.
- [x] 8.3 Implement export service: if LUT == Natural, `AVAssetExportSession(preset: .passthrough)` with `timeRange` → <1 s on iPhone 14+; else compose `AVMutableComposition` + `CIFilter.colorCube` path via `CIContext(mtlDevice: MTLCreateSystemDefaultDevice())` singleton; measure and assert <1 s passthrough.
- [x] 8.4 Wire four LUT presets to bundled cubes: Natural (skip filter), Warm Studio, Cinematic Contrast, Clean Monochrome (grayscale luminance); combined trim+LUT in single pass; handle export errors (disk full, invalid range) with alert and retain original.
- [x] 8.5 Implement Photos save: `PHPhotoLibrary.requestAuthorization(for: .addOnly)`, `performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo }`, delete sandbox source on success, retain on failure; alert + Settings link on denial.
- [x] 8.6 Add `ShareLink(item: outputURL)` share sheet; verify shared file is processed output (trimmed/graded) and AirDrop/Messages/Instagram/TikTok destinations appear.
- [x] 8.7 Unit/UI tests: trim range math, export success/failure, Photos auth denied path (mock), ShareLink existence; manual export timing on device for 30 s take.

## 9. Audio Routing, Preferences & AppIntents (spec: audio-settings-intents)

- [x] 9.1 Configure `AVAudioSession` in `CaptureService` or `AudioService`: `setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth, .allowBluetoothA2DP])` + `setActive(true)`; observe `routeChangeNotification` to update UI label (AirPods/Rode/DJI/Wired).
- [x] 9.2 Implement VU metering: `AVCaptureAudioDataOutput` RMS → dBFS or `AVAudioRecorder` metering, update at ≥10 Hz via `TimelineView`; display `ProgressView`/level bars with clip indicator at 0 dBFS; silence rests at floor (-60 dBFS/-∞).
- [x] 9.3 Add `@AppStorage` defaults for `resolution` (default 1080p), `frameRate` (30), `mirrorMode` (true), `countdownSeconds` (3), `aspectRatio` (16:9), `lutPreset` (Natural); verify persistence across force-quit/relaunch.
- [x] 9.4 Implement `AppIntents`: `RecordScriptIntent` + `OpenScriptIntent` with `Parameter` for `scriptID/title`, `AppShortcutsProvider` exposing "Record a script in OneTake" phrase; handle missing-script fallback to library with not-found message.
- [ ] 9.5 Test on Settings → Action Button mapping; verify intents appear in Shortcuts app with parameters; manual test with AirPods + Rode Wireless GO.

## 10. Polish, Testing & Device Validation

- [x] 10.1 Add `#Preview` for all major views (library empty/populated, editor, studio preview, tweak tray, review) with in-memory `ModelContainer`; add snapshot/UI tests for SwiftUI layers only (no AVFoundation in CI).
- [x] 10.2 Define `#if targetEnvironment(simulator)` fallbacks for `AVCaptureSession`, `CHHapticEngine`, `ActivityKit` so CI builds pass; gate device-only tests behind runtime checks.
- [x] 10.3 File hygiene: store relative paths in SwiftData, resolve via `FileManager.default.urls(for: .documentDirectory)`; evict sandbox cache after Photos save; handle file URL invalidation after app update.
- [x] 10.4 Thermal/power: monitor `ProcessInfo.thermalState` → auto-downgrade from 4K/60 to 1080p with user banner when `.critical`; default to 1080p30 to preserve battery.
- [ ] 10.5 Full manual QA on physical devices (iPhone SE, 14, 15 Pro): capture matrix, ProMotion scroll, tweak tray live, Dynamic Island/Lock Screen, haptics, trim <1 s, LUT presets, Bluetooth routing, Siri/Action Button, Photos save + ShareLink.
- [ ] 10.6 App Store readiness: verify no private API usage, privacy strings present, Live Activities entitlement correct, background mode justification only if needed (foreground-only recording).

