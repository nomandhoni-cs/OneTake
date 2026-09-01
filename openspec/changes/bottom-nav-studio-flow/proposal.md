## Why

The current app is a single `NavigationStack` rooted at the Scripts list; there is no persistent navigation, no way to browse takes without opening a script, and the Studio camera is a pushed detail that hides settings inline and has no pause. Users request a familiar bottom tab structure (My Takes / Scripts / Profile) with a prominent center Studio CTA, plus in-camera script switching, a proper settings bottom sheet, and pause/resume for multi-segment takes. Without this, the app feels like a prototype list rather than a daily-use capture tool.

## What Changes

- **BREAKING**: Replace `ContentView` single `NavigationStack` with a 5-item bottom bar shell: `[My Takes] [Scripts] [● Studio] [Profile]` — Studio is a centered, elevated CTA button (not a tab) presenting the camera full-screen. Each tab maintains its own `NavigationStack` state and search/filter.
- Add **My Takes** tab: list of all `Take` records across all scripts (reverse-chronological), grouped by day, with thumbnail/preview, script title link, duration, trim/lut indicators, `ContentUnavailableView` empty state, `.searchable` over script title, and swipe actions; tapping opens Review.
- Enhance **Review** (trim-color-export) from My Takes: explicit **Edit** flow (re-trim, change LUT, re-export as new take or overwrite), **Delete** with file cleanup, and **Export/Share** (`PHPhotoLibrary` + `ShareLink`) — exposed via toolbar/ellipsis and swipe actions from My Takes.
- Add **Profile** tab: static/preference screen with app settings entry points (camera defaults from `StudioSettings`/`@AppStorage`, links to Review Profile), about/version, and future auth placeholder; grouped inset list.
- Move **Studio** to a modal-like full-screen camera shell: top bar holds `ScriptSelector` (dropdown/picker of all scripts, plus “No script” freestyle), and bottom bar holds Record/Pause/Resume/Stop + settings gear that opens a **bottom sheet** (not inline tray).
- Add **script selector on camera**: picker bound to `@Query` scripts; changing script mid-preview swaps `PrompterView` text instantly without restarting the session; selection persists per app launch and survives sheet dismiss.
- Relocate **camera settings to bottom sheet**: resolution, frame rate, HDR, mirror, countdown toggle, aspect ratio — presented as `.sheet(detents: [.medium, .large])` with segmented pickers and toggles; unsupported combinations disabled with explanation, changes apply live to the running `CaptureService` session.
- Add **pause/resume recording**: `AVCaptureMovieFileOutput` segment handling (or `AVAssetWriter` segment merge) so Record → Pause freezes file segment and prompter scroll + timer, Resume continues same take file (merged) and restarts scroll/timer and Live Activity; Paused state shows dimmed preview, resume prompt, and does not finalize the `Take` until Stop.
- Keep **Scripts** tab behavior: current `ScriptLibraryView` becomes Scripts root, search/swipe/duplicate/delete/editor sheet unchanged but “Record with Prompter” now opens the Studio CTA sheet with the script pre-selected (instead of pushing on the same stack).

## Capabilities

### New Capabilities

- `app-navigation`: Bottom tab shell with My Takes / Scripts / centered Studio CTA / Profile, per-tab NavigationStacks, state restoration, and deep-link routing.
- `takes-library`: My Takes list (all Takes aggregated, grouped by day, search/filter, swipe actions, empty states, navigation to Review).
- `user-profile`: Profile tab (settings links, app info, preferences entry, placeholder sections).
- `studio-controls`: In-camera script selector + pause/resume lifecycle (timer, prompter, Live Activity, file segment merge).

### Modified Capabilities

- `capture-engine`: Pause/resume segment handling, settings sheet driving live `CaptureService` reconfiguration, and foreground/pause/background lifecycle refinements.
- `prompter-studio`: Move tweak controls (speed/font/opacity/aspect) into + adapt to bottom sheet presentation; freeze/resume scroll on pause; support live script swapping.
- `trim-color-export`: Extend Review to support Edit (re-trim/LUT), Delete, and Export/Share entry points triggered from My Takes.

## Impact

- **Code**: `ContentView.swift` rewritten to tab shell; new files `Features/Takes/MyTakesView.swift`, `Features/Profile/ProfileView.swift`, `Features/Studio/ScriptSelectorView.swift`, `Features/Studio/StudioSettingsSheet.swift`, `Core/Capture/PauseController` (or extension to `CaptureService`); `StudioView.swift` refactored to accept optional initial `Script` + selector binding + pause state + sheet presentation.
- **UX**: Entire navigation idiom changes; users land on My Takes by default; Scripts remains but is no longer the launch screen; Studio is no longer push-navigated.
- **Data**: No schema change; `Take` already stores `scriptID` + `relativeFilePath` + trim/LUT. Pause may introduce temp segment files merged on Stop; need atomic merge to avoid orphan files.
- **Risks**: Pausing `AVCaptureMovieFileOutput` is not natively supported — requires `pauseRecording` (iOS 18 `AVCaptureMovieFileOutput` adds pause) or manual segment-files-then-merge via `AVMutableComposition`. Choose based on deployment target (18.6 → `isRecordingPaused` path exists). Sheet + tab state must not deallocate running `AVCaptureSession`.
