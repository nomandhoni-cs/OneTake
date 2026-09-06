## 1. Model + Navigation Shell

- [x] 1.1 Add additive `Take` fields (`isReaction`, `backgroundAssetLocalID` with defaults) and register in `Schema` + previews/tests containers
- [x] 1.2 Convert `StudioTab` to 2-card mode picker (Teleprompter / Reaction) with 44pt targets, VoiceOver labels, and `StudioMode` enum
- [x] 1.3 Present both modes via `fullScreenCover` (tab bar hidden), dismiss back to picker, guard tab-switch/deep-link during recording with leave-confirmation

## 2. Background Source

- [x] 2.1 Add `PHPickerViewController` BG picker (video/image) with replace-while-previewing and Restart-BG transport
- [x] 2.2 Reject DRM/protected clips at pick time with explanatory alert; keep previous background
- [x] 2.3 Drive BG playback via `AVPlayer` + `AVPlayerItemVideoOutput` (video) / static `CIImage` (photo) as compositor input

## 3. Segmentation + Compositing

- [x] 3.1 Create `ReactionCompositor` (Metal `CIContext`, `CIBlendWithMask`, mask align/scale, circle-crop + split-screen transforms, dilated-mask outline glow)
- [x] 3.2 Wire `VNGeneratePersonSegmentationRequest` (.balanced) on background queue with temporal mask-hold skip when over budget
- [x] 3.3 Feed one composited path to both SwiftUI preview (`CAMetalLayer`) and writer input (WYSIWYG); add A14 fallback (unmasked rect + caption)

## 4. Reaction Capture + Audio

- [x] 4.1 Create `ReactionCaptureService` (`@Observable`, video/audio data outputs, BG-clock timestamps, `AVAssetWriter` H.264 1080p30 SDR) reusing `AudioSessionService`/`ThermalMonitor`/`HapticsService`/`RecordingActivityService`
- [x] 4.2 Implement `ReactionAudioMixer` (mic + BG mix, VAD ducking to 30% with ~150ms attack/~800ms release, Duck toggle, BG volume slider, dual mic/BG meters)
- [x] 4.3 Implement pause/resume (BG player pause + merged single MP4, no orphans) and backgrounding/interruption auto-finalize; hide HDR toggle with SDR caption in reaction settings

## 5. Reaction UI + Prompter Overlay

- [x] 5.1 Build `ReactionStudioView` (full-screen: frosted prompter top, BG + cutout canvas, cutout control bar, transport + REC row per wireframe)
- [x] 5.2 Add draggable + pinch-scalable presenter rect with `@AppStorage` persistence and live layout/outline switching without session restart
- [x] 5.3 Embed optional script picker (freestyle default, `lastScriptID` reuse, deleted-script fallback) + `PrompterView` overlay with pause-freeze semantics

## 6. Takes Integration + Quality Gates

- [x] 6.1 Save composited MP4 as `Take(isReaction: true)` with reaction badge/filter in My Takes; verify blade/trim/LUT/export parity
- [x] 6.2 Add tests (`ReactionCompositorTests`: layout transforms, mask align; `ReactionAudioMixerTests`: ducking attack/release; UI test: picker → reaction → record → take appears)
- [x] 6.3 Run `swiftformat`, `swiftlint` (0 violations), `xcodebuild build + test`, and update `docs/ARCHITECTURE.md`, `docs/CODEMAP.md`, `AGENTS.md`
