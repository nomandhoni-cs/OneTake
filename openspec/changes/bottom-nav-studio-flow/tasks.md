## 1. App Navigation Shell

- [x] 1.1 Create `RootTabView` with `enum Tab { takes, scripts, profile }` + `showStudio` + three `NavigationPath` states; render `TabView(selection:)` with My Takes / Scripts / Profile `TabItem`s and a centered overlay Studio CTA (elevated circular button, 64pt, shadow) presenting `.fullScreenCover`.
- [x] 1.2 Rewrite `ContentView` to render `RootTabView` behind feature flag `ENABLE_TAB_SHELL` (default ON) while preserving old `NavigationStack` for snapshot tests; wire `SceneStorage`/`AppStorage` for selected tab persistence and add VoiceOver labels (44pt hit target) for all tab items + Studio CTA.
- [x] 1.3 Extend shared `Route` for per-tab destinations (Studio already via cover, Review on My Takes/Scripts stacks, Editor on Scripts/Profile) and verify deep link “Record with Prompter” from `ScriptEditorSheet` opens Studio cover with pre-selected script (use `lastScriptID`).
- [x] 1.4 Ensure Studio cover owns `AVCaptureSession` lifecycle: `onDisappear` calls `stopSession` + `stopMetering` + `end` Live Activity so backgrounded cover does not drain battery; verify switching tabs while Studio presented keeps cover alive.

## 2. My Takes Library

- [x] 2.1 Build `MyTakesView` under `Features/Takes/` with `@Query(sort: \Take.createdAt, reverse)`, day-grouped via `Dictionary(grouping:)` (Today/Yesterday/date header), joining `Script` titles via `scriptID` dictionary; show duration/`lutPreset` badge/trim indicator and file-existence check with “File missing” indicator.
- [x] 2.2 Add `.searchable` filtering over resolved script title (case-insensitive) and empty/error states: zero takes → `ContentUnavailableView` “No takes yet” + CTA “Record your first take” opening Studio; no search results → `ContentUnavailableView.search`.
- [x] 2.3 Add swipe actions: trailing Delete (destructive, confirmation) → delete file + `modelContext.delete` + segment temp cleanup, animation; leading Edit → push `ReviewView(take:)` in edit mode on My Takes stack.
- [x] 2.4 Wire row tap to push `ReviewView` onto My Takes stack with shared `AVPlayer` preview; Verify `ContentUnavailableView` used for all empty states; add `#Preview` with in-memory store (0 takes, 5 takes, missing file, searching).

## 3. Profile Tab

- [x] 3.1 Create `ProfileView` as grouped inset list with sections Preferences (Camera defaults / Countdown / Aspect / LUT), Takes summary (count + total duration live from Takes query), About (version/build + privacy link), and future account placeholders; each row pushes detail on Profile stack.
- [x] 3.2 Maintain independent `NavigationStack` state for Profile (retain detail depth across tab switches); add `#Preview` (populated/empty summary).

## 4. Studio — Script Selector + Settings Sheet + Pause/Resume

- [x] 4.1 Build `ScriptSelectorView` `Menu`/`Picker` in Studio top bar bound to `selectedScriptID: Script.ID?` + `@Query` scripts + “No script — Freestyle” option; on change, swap `PrompterView(text:)` instantly without restarting session; persist to `@AppStorage("lastScriptID")`; fallback to “No script” when ID deleted with transient indicator.
- [x] 4.2 Create `StudioSettingsSheet` presented via `.sheet(detents: [.medium, .large], dragIndicator: .visible)` containing resolution/frame-rate `Picker`s, HDR/mirror/countdown toggles, aspect `Picker`; disable unsupported res/fps combos + format controls (res/fps/HDR) while `isRecording || isPaused` with banner “Stop recording to change camera format”; bind to existing `@AppStorage` + live `resolution`/`frameRate` → `captureService.configure`.
- [x] 4.3 Extend `CaptureService` with `pauseRecording()`/`resumeRecording()` using `responds(to:)` check for `pauseRecording`/`resumeRecording` (iOS 18.6) else fallback to sequential segment files under `takes/segments/<uuid>/seg-###.mp4`; on Stop merge via `AVMutableComposition` + `AVAssetExportSession` then delete segments; on failure retain segments and surface alert.
- [x] 4.4 Wire pause/resume through Studio controls + state machine: preview→Record, recording→Pause+Stop, paused→Resume+Stop; Pause freezes prompter scroll + REC timer + sends single paused Live Activity update; Resume restarts scroll/timer + Live Activity recording state; auto-`stopRecording` on background/interruption while paused; haptics on each transition; final `Take` stores `scriptID` from selector at Stop time and appears in My Takes.
- [x] 4.5 Move tweak controls (speed/font/opacity/aspect) from inline `TweakTrayView` into `StudioSettingsSheet` (shared `Observable`/`@State` so dismiss does not lose values); update `PrompterView` to observe same bindings + add `isPaused` freeze (retain offset, `speed` changes don’t advance scroll); verify sheet does not interrupt running preview.
- [x] 4.6 Add `#Preview` for `StudioView` script-selector states (No script, 3-script picker, paused badge) and `StudioSettingsSheet` (recording-disabled state, unsupported combo).

## 5. Review Edit From My Takes

- [x] 5.1 Extend `ReviewView` with edit mode (triggered from My Takes swipe) allowing re-trim (`TrimScrubberView` dual-handle) and LUT re-select then re-export via `ExportService` (passthrough vs `CIFilter.colorCube`); add “Save as New Take” (insert new `Take` preserving original) and “Replace” (atomically update `relativeFilePath` + delete old file) actions plus error path retaining original and allowing retry.
- [x] 5.2 Implement My Takes Delete confirmation sheet: remove file + `Take` + segment temp dir cleanup; handle file-missing takes (delete record only) without crash.

## 6. Polish & Testing

- [x] 6.1 Add unit tests for new pure logic: `ScriptSelectorView` title resolution (missing ID → freestyle), My Takes grouping/search, `TakesLibrary` delete/edit routing, and pause state machine single-file invariant (mock `CaptureService` pause selector).
- [x] 6.2 Add `#if targetEnvironment(simulator)` fallbacks for new pause selectors so `xcodebuild` CI passes without device; gate device-only assertions behind `TARGET_OS_SIMULATOR == 0`.
- [ ] 6.3 Run device manual QA: tab state retention (Scripts editor depth across tab switch), Studio cover not dismissed by tab tap, script switch mid-preview, sheet disable-while-recording banner, pause/resume ×3 → Stop single file, background while paused auto-finalize, My Takes Edit/Delete/Share and Profile stack retention.
- [x] 6.4 Verify App Store readiness: no private API beyond `responds(to:)` for `pauseRecording`; privacy strings remain present; Live Activities entitlement unchanged; background mode stays foreground-only (pause finalizes on background).

