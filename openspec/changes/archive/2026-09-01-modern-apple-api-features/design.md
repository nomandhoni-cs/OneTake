## Context

OneTake is a greenfield iOS app currently at the Xcode SwiftData template stage (`OneTakeApp.swift:13` `ModelContainer`, `ContentView.swift:13` `@Query [Item]`, `Item.swift:11` `@Model`). There is no domain model, no capture pipeline, and no design system. The spec demands a zero-dependency, first-party Apple stack: SwiftUI + Observation for UI/state, SwiftData for offline persistence, AVFoundation for 1080p/4K capture, CoreImage/Metal for GPU LUT grading, AVAssetExportSession for stream trimming, ActivityKit for Dynamic Island, CoreHaptics for tactile feedback, AVAudioSession for Bluetooth routing, and AppIntents for Siri/Action Button.

Constraints: iOS 17+ minimum (SwiftData + Observation + modern ActivityKit), real hardware required for AVFoundation/CoreHaptics/ActivityKit validation (simulator insufficient), must handle camera/mic privacy, Live Activities entitlement, and sandbox file hygiene. Stakeholders: solo developer / App Store review.

## Goals / Non-Goals

**Goals:**
- Establish canonical SwiftData schema (`Script`, `Take`, app preferences) with `@Observable` view models and `NavigationStack` routing that replaces the template `NavigationSplitView`.
- Deliver a reliable `AVCaptureSession` pipeline supporting 1080p/4K at 24/30/60 fps, HDR/Dolby Vision, and AE/AWB/AF freeze on record, with correct lifecycle (foreground/background, interruption, route change).
- Ship ProMotion-locked 120 Hz prompter scroll anchored to the lens (Dynamic Island/notch) using native materials.
- Provide sub-second trim and GPU LUT export that never blocks the main thread and writes directly to Photos via `PHPhotoLibrary`.
- Surface live recording state in Dynamic Island/Lock Screen and provide haptic countdown with graceful degradation.
- Route audio to Bluetooth/wired external mics with live VU metering.
- Persist user defaults via `@AppStorage` and expose Siri/Action Button via `AppIntents`.

**Non-Goals:**
- Cloud sync, collaboration, or backend services (offline-first SwiftData only).
- Custom video codec/encoder or non-Apple GPU framework (no FFmpeg, no third-party LUT library).
- macOS/visionOS targets, iPad multitasking optimizations, or watchOS companion.
- AI transcription, auto-captions, or LLM-driven script generation.
- In-app purchase / paywall.

## Decisions

### 1. State: `@Observable` macro over `ObservableObject` / `@StateObject`
**Decision:** All view models become `@Observable` classes (iOS 17+), injected via `@Environment` or `@State`. SwiftUI views use `@Bindable` where mutation is needed.
**Rationale:** Observation tracks property-level dependencies (finer invalidation than `objectWillChange`), integrates natively with SwiftData's `@Model` observation, and eliminates `Combine` boilerplate. Aligns with Apple's 2023+ guidance.
**Alternatives considered:** `ObservableObject` + `@Published` — rejected due to coarse invalidation and redundancy with SwiftData; TCA/ReSwift — rejected (zero-dependency constraint).

### 2. Persistence: SwiftData `@Model` with single `ModelContainer`
**Decision:** Define `@Model final class Script { id, title, body, createdAt, updatedAt, durationEstimate, takes: [Take] }` and `@Model final class Take { id, scriptID, fileURL, createdAt, duration, trimRange, lutPreset }`. Single `ModelContainer` in `OneTakeApp.swift:13` configured `isStoredInMemoryOnly: false`. Autosave on every `body` keystroke via `modelContext.autosaveEnabled` / manual `save()` debounce (300 ms).
**Rationale:** SwiftData provides instant persistence, `@Query` live filtering, and iCloud-ready schema without Core Data boilerplate. `@Model` already in template so migration is additive.
**Alternatives:** Core Data directly — more control but unnecessary complexity; Realm/GRDB — violates zero-dependency rule.

### 3. Navigation: `NavigationStack` + path, not `NavigationSplitView`
**Decision:** Root `NavigationStack(path:)` with enum `Route { library, editor(Script), studio(Script), review(Take) }`. Lists use `.insetGrouped`, `.searchable()`, `.swipeActions`, `ContentUnavailableView`.
**Rationale:** Stack is correct for iPhone single-column teleprompter flow; `NavigationSplitView` is iPad-oriented. Path-based navigation enables programmatic "Record with Prompter" push and deep-link via `AppIntents`.
**Alternative:** Keep `NavigationSplitView` — rejected, adds empty detail column on iPhone.

### 4. Capture Pipeline: Actor-isolated `CaptureService` on dedicated queue
**Decision:** `actor CaptureService` owns `AVCaptureSession`, `AVCaptureDeviceInput` (front wide-angle), `AVCaptureMovieFileOutput` (or `AVCaptureVideoDataOutput` if frame-processing needed), and `AVCaptureAudioDataOutput`. Session configuration on `sessionQueue = DispatchQueue(label: "onetake.session")`. Resolution/fps selection via `device.activeFormat` + `AVCaptureDevice.Format` filtering (1080p = 1920×1080, 4K = 3840×2160) and `activeVideoMin/MaxFrameDuration`. HDR via `isVideoHDREnabled` where available. On `startRecording()`, call `device.lockForConfiguration(); device.exposureMode = .locked; device.whiteBalanceMode = .locked; device.focusMode = .locked; unlock`.
**Rationale:** AVFoundation is not thread-safe; actor + serial queue prevents deadlocks. `MovieFileOutput` is sufficient for file-based capture without per-frame processing (simpler than `VideoDataOutput` + `AVAssetWriter`).
**Alternatives:** `AVCaptureVideoDataOutput + AVAssetWriter` — more flexible but complex, needed only if real-time LUT preview is required (deferred).

### 5. Prompter Scroll: `TimelineView(.animation)` primary, `CADisplayLink` fallback
**Decision:** `TimelineView(.animation(minimumInterval: 1/120))` drives `offsetY += pointsPerSecond * deltaTime`. `pointsPerSecond = baseSpeed * scrollMultiplier` where `scrollMultiplier` maps slider 1.0–4.0×. Precompute `deltaTime` from `TimelineView` context date. Fallback to `CADisplayLink` on devices where `TimelineView` cadence is throttled (measured via Instruments). Prompter container: `RoundedRectangle` + `.ultraThinMaterial` + `stroke` eye-line accent, pinned via `safeAreaInset(edge: .top)` accounting for `DynamicIsland` height.
**Rationale:** `TimelineView` is SwiftUI-native, respects ProMotion and low-power mode automatically; `CADisplayLink` is UIKit imperative and harder to coordinate with SwiftUI state. Using both covers edge cases where `TimelineView` skips frames under load.
**Alternatives:** `Timer` / `withAnimation` — rejected (not display-linked, drops frames).

### 6. Tweak Tray & Aspect Masks
**Decision:** Bottom sheet / inline tray with `Slider(value:in:step:)` (speed 1.0–4.0× step 0.1, font 18–36 pt step 1, opacity 0–0.8 step 0.05) + `Stepper` buttons sharing the same `@Bindable` source of truth. Haptics on stepper via `CoreHaptics` or `UIImpact`. Aspect masks as overlay `Color.black` letterbox/pillarbox with `matchedGeometryEffect` animation between ratios.
**Rationale:** Dual controls (continuous + discrete) satisfy spec verbatim; shared state prevents drift.
**Alternative:** Only slider or only stepper — rejected, spec requires both.

### 7. Live Activity & Dynamic Island: `ActivityKit` with `ActivityAttributes`
**Decision:** `struct RecordingAttributes: ActivityAttributes { struct ContentState: Codable, Hashable { var elapsedSeconds: Int; var audioLevel: Float; var isRecording: Bool } }`. Start activity on `captureService.startRecording()`, update every second via `activity.update(using:)`, end on `stopRecording()`. Define `LiveActivity` widget extension (`ActivityConfiguration`) for Lock Screen + Dynamic Island compact/expanded views. Requires `NSSupportsLiveActivities` + Live Activities entitlement.
**Rationale:** `ActivityKit` is the only Apple-sanctioned path to Dynamic Island; no private API alternative.
**Fallback:** If `ActivityAuthorizationInfo.areActivitiesEnabled == false`, show in-app HUD only.

### 8. Haptics: `CHHapticEngine` with `UIFeedbackGenerator` fallback
**Decision:** `HapticsService` lazily starts `CHHapticEngine`, pre-warms on studio appear, handles `engine.resetHandler`. Countdown pattern: two `CHHapticEvent(eventType: .hapticTransient, ...)` at t=3s,2s (intensity 0.6) and one `hapticContinuous` burst at t=0 (intensity 1.0, duration 0.3s). If `CHHapticEngine.capabilitiesForHardware().supportsHaptics == false`, fall back to `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`.
**Rationale:** `CoreHaptics` allows custom waveforms; `UIFeedback` is limited to presets but universally available.
**Alternative:** Only `UIFeedbackGenerator` — rejected, cannot reproduce spec's "intense continuous burst".

### 9. Trim: `AVAssetExportSession` passthrough with `CMTimeRange`
**Decision:** Dual-handle `Slider` / custom trim view producing `CMTimeRange(start: trimmedStart, duration: trimmedDuration)`. Export via `AVAssetExportSession(asset: AVAsset(url: sourceURL), presetName: AVAssetExportPresetPassthrough)` (or `HighestQuality` if re-encode needed for LUT). Set `timeRange` and `outputFileType = .mp4`. For trim-only (no LUT), passthrough completes <1 s without re-encode. For trim+LUT, compose via `AVMutableComposition` + `CIFilter` render pass then export.
**Rationale:** Passthrough is hardware-accelerated stream copy, satisfying "sub-second" requirement. Re-encode only when pixel modification (LUT) is requested.
**Alternative:** `AVMutableComposition` + `AVAssetExportSession` always re-encoding — slower, unnecessary for trim-only.

### 10. Color Grading: `CIFilter.colorCube` on Metal GPU
**Decision:** Store 3D LUTs as 64×64×64 `Data` cubes (pre-baked `.cube` files converted to `NSData`). Apply via `CIFilter.colorCube(inputImage:cubeData:cubeDimension:)`. Render chain: `CIImage -> CIFilter -> CIContext(mtlDevice: MTLCreateSystemDefaultDevice()) -> CGImage`. Four presets map to four cube files: natural (identity-ish), warmStudio, cinematicContrast, monochrome. Apply at export time (not live preview) to preserve capture performance; optional live preview via `AVCaptureVideoPreviewLayer` + `CIFilter` is stretch goal.
**Rationale:** `colorCube` runs on Apple Silicon GPU via Metal, zero third-party code, matches spec exactly. Identity cube is no-op baseline.
**Alternative:** Custom Metal shader — more power but unnecessary; `CIFilter` already wraps Metal.

### 11. Review & Save: `AVKit.VideoPlayer` + `PHPhotoLibrary` + `ShareLink`
**Decision:** `VideoPlayer(player: AVPlayer(url: takeURL))` for instant preview (no pre-render). On Save, `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL) }` with `PHPhotoLibrary.requestAuthorization(for: .addOnly)`. Delete sandbox cache after successful save (`FileManager.removeItem`). Share via `ShareLink(item: outputURL)` which presents native sheet (AirDrop, Messages, Instagram, TikTok).
**Rationale:** All native, no custom share logic needed.
**Alternative:** `UIActivityViewController` — still valid but `ShareLink` is SwiftUI-native.

### 12. Audio Routing: `AVAudioSession` `.videoRecording` + VU metering
**Decision:** Configure `try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth, .allowBluetoothA2DP])` and `setActive(true)`. Observe `AVAudioSession.routeChangeNotification` to detect AirPods/Rode/DJI. VU via `AVAudioRecorder` metering or `AVCaptureAudioDataOutput` sample buffer RMS → dBFS. Display as `ProgressView` / level meter updating via `TimelineView`.
**Rationale:** `.videoRecording` optimizes for camera + mic; `.allowBluetooth` enables wireless mics as required.
**Alternative:** `.record` category — less appropriate for simultaneous video.

### 13. Preferences & Intents: `@AppStorage` + `AppIntents`
**Decision:** `@AppStorage("resolution") var resolution: String = "1080p"` etc. for resolution, fps, mirror, countdown. `struct RecordScriptIntent: AppIntent { @Parameter var scriptID: String; func perform() async throws -> some IntentResult { open app / start capture } }` with `AppShortcutsProvider` exposing "Record a script in OneTake". Map Action Button via Shortcuts.
**Rationale:** `@AppStorage` is UserDefaults-backed and SwiftUI-reactive; `AppIntents` is the modern Siri/Shortcuts/Action Button API replacing legacy `INIntent`.
**Alternative:** Manual `UserDefaults` + `INIntent` — older API, more boilerplate.

## Risks / Trade-offs

- **Simulator cannot test capture/haptics/live activities** → Mitigation: Require physical device for QA; gate CI with `#if targetEnvironment(simulator)` fallbacks and snapshot tests for UI only.
- **AVCaptureSession interruptions (phone call, route change)** → Mitigation: Observe `AVCaptureSession.wasInterruptedNotification` / `AVAudioSession.interruptionNotification`; pause prompter, show banner, resume on `interruptionEnded`.
- **Live Activity update throttling (4 updates/sec limit)** → Mitigation: Throttle updates to 1 Hz; batch audio level + timer; handle `ActivityAuthorizationInfo` denial gracefully.
- **CHHapticEngine stops on app background / audio session conflict** → Mitigation: Re-start engine in `resetHandler` and on `scenePhase == .active`; fallback to `UIFeedbackGenerator` if engine fails.
- **SwiftData migration on schema change** → Mitigation: Versioned schema with `SchemaMigrationPlan`; template data is disposable so lightweight migration is acceptable for v1.
- **4K/60 + HDR power/thermal** → Mitigation: Offer 1080p default, warn on 4K/60, monitor `ProcessInfo.thermalState` and auto-downgrade if `.critical`.
- **PHPhotoLibrary permission denial** → Mitigation: Pre-flight `authorizationStatus`; show `ContentUnavailableView` with Settings deep-link if denied; never crash on save.
- **Metal CIContext creation cost** → Mitigation: Singleton `CIContext(mtlDevice:)` reused; lazy init; release on memory warning.
- **File URLs invalidated after app restart** → Mitigation: Store relative paths in SwiftData, resolve via `FileManager.default.urls(for: .documentDirectory)`; copy exported file before Photos save.

## Migration Plan

1. **Branch & scaffold:** Create feature branch; add `Info.plist` keys (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSupportsLiveActivities`), Live Activities entitlement, and `OneTake/Features/{Workspace,Studio,Review,Settings}` folder structure.
2. **Model layer:** Replace `Item` with `Script`/`Take` `@Model` classes; update `OneTakeApp.swift:13` `Schema([Script.self, Take.self])`; add lightweight migration plan; verify SwiftData persistence on device.
3. **Workspace:** Build library list + editor sheet; gate behind `ContentUnavailableView` empty state; unit testword count / 130 wpm logic.
4. **Capture:** Implement `CaptureService` actor + preview layer (`UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`); manual device test for 1080p/4K/fps/HDR + lockForConfiguration.
5. **Prompter & HUD:** Add `TimelineView` scroller, tweak tray, aspect masks, `ActivityKit` extension, `CoreHaptics` countdown; Instruments frame-rate audit for 120 Hz.
6. **Review pipeline:** Wire `VideoPlayer`, trim scrubber → `AVAssetExportSession`, LUT cubes → `CIFilter.colorCube`, `PHPhotoLibrary` save, `ShareLink`; measure trim <1 s on iPhone 14+.
7. **Audio/Intents:** Configure `AVAudioSession`, VU meter, `@AppStorage` defaults, `AppIntents` shortcuts; test with AirPods + Rode.
8. **Polish & rollback:** Snapshot/UI tests for SwiftUI layers; manual device matrix (iPhone SE → 15 Pro). Rollback is revert branch — no data migration to undo beyond deleting new SwiftData store (acceptable for pre-launch).

## Open Questions

- **Minimum device matrix for 4K/60 HDR:** Which formats are guaranteed on iPhone 12 vs 15 Pro? Need runtime `device.formats` enumeration and fallback UI if 4K/60 unavailable.
- **Live preview LUT:** Should LUT be previewed live in capture (costly) or only at export? Proposal says export-time; confirm product intent before adding real-time `CIFilter` to preview pipeline.
- **Take storage quota:** Should sandbox cache auto-evict oldest takes after N GB, or require manual delete? Spec says "automatic sandbox cache cleanup" on Photos save only — clarify retention policy for unsaved takes.
- **Mirroring default:** Front-camera preview is mirrored by default in `AVCaptureVideoPreviewLayer`; should saved file also be mirrored (user-facing) or unmirrored (true camera)? Need UX decision.
- **AppIntents parameter design:** Does "Hey Siri, record a script in OneTake" require disambiguation (list scripts) or just open library? Affects `AppShortcuts` phrasing.
- **Background recording policy:** If user backgrounds app mid-record, should capture auto-stop or continue via background mode? Spec implies foreground-only; confirm to avoid App Store background-mode justification.
