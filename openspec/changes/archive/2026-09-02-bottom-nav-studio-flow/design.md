## Context

After `modern-apple-api-features` (archived 2026-09-01) the app has seven shipped specs and a working but nav-poor shell: `ContentView` is a single `NavigationStack` over `ScriptLibraryView`; Studio is a `navigationDestination` push with inline tweak tray; there is no Takes browsing and no Profile. The new request adds persistent bottom navigation (My Takes / Scripts / Profile + centered Studio CTA), moves camera settings into a bottom sheet, adds in-camera script switching, and adds pause/resume — all on iOS 18.6, SwiftUI + SwiftData, zero third-party deps, with the synced 64³ LUT cubes and `PBXFileSystemSynchronizedRootGroup` project structure.

## Goals / Non-Goals

**Goals:**
- Ship a tab shell that retains per-tab navigation state (including search + sheet) and presents Studio as a full-screen cover that owns the `AVCaptureSession` lifecycle.
- Provide My Takes as the default landing tab (aggregated Takes with search, day grouping, empty states, and Review entry points).
- Make Studio usable without leaving the camera: script picker at top, settings gear → sheet, and pause/resume that correctly freezes prompter scroll, timer, Live Activity, and file segments.
- Keep existing Scripts and Review behavior intact, just re-parented under tabs/sheet.

**Non-Goals:**
- Schema migration (no new `@Model` fields; pause reuses segment files merged on stop).
- Cloud sync, auth, or subscription paywall.
- Redesigning trim/LUT/export pipeline beyond “Edit from My Takes”.
- iPad/SplitView layout.

## Decisions

### 1. Tab shell: `TabView` + per-tab `NavigationStack` + full-screen Studio cover
**Decision:** `RootTabView` owns `enum Tab { takes, scripts, profile }` + `Bool showStudio` + three `NavigationPath`/`NavigationStack` roots. Tabs use `TabView(selection:)`; Studio CTA is a custom centered button overlay (not a tab item) that sets `showStudio = true` → `.fullScreenCover { StudioView }`. Each tab’s stack pushes `Review`/`Editor` as before via shared `Route` extended for tab-local destinations.
**Rationale:** Keeps per-tab back stacks (expected by HIG), avoids pushing Studio onto a tab stack where the session would be torn down on pop. `.fullScreenCover` keeps capture session alive and maps to the “separate button” requirement.
**Alternative:** Make Studio a fourth tab — rejected because capture should be chrome-free and the spec calls it a separate button; tab would also imply persistence where none is desired.

### 2. My Takes as aggregated `@Query` view
**Decision:** `MyTakesView` does `@Query(sort: \Take.createdAt, order: .reverse) var takes: [Take]` plus in-memory join to `Script` titles via dictionary (`scriptID → title`). Grouped by day via `Dictionary(grouping:)`. Search filters on resolved script title (case-insensitive). Row shows duration, `lutPreset` badge, trim indicator, and `fileURL` existence check.
**Rationale:** Takes are already linked to scripts; storing script title denormalized would duplicate. Join is O(n) and tiny (<1k rows).
**Alternative:** Create `TakesLibraryViewModel` with `FetchDescriptor` predicate — rejected, no predicate on joined title; filtering after fetch is simpler and keeps `@Query` live updates.

### 3. Pause/resume: prefer `AVCaptureMovieFileOutput.isRecordingPaused` (iOS 18+) else segment merge
**Decision:** Check `movieOutput.responds(to: Selector(("pauseRecording")))` at runtime. If available (deployment is 18.6, so yes), call `pauseRecording()` / `resumeRecording()`. While paused, freeze `TimelineView` tick, stop the 1 Hz Live Activity updates (send a paused state once), and disable shutter. On `stopRecording`, if paused path was used, file is already contiguous — no merge. Add fallback path: if pause selectors missing, record to sequential segment files (`takes/segments/<uuid>/seg-001.mp4` etc.) and on Stop merge via `AVMutableComposition` → `AVAssetExportSession` then delete segments; if merge fails, keep segments and surface error without losing data.
**Rationale:** Paused output is exact and avoids re-encode; fallback keeps system working on any future OS or test harness.
**Alternative:** Always segment-merge — rejected, re-encode cost on every pause.

### 4. Script selector lives in Studio top bar, drives `@Binding Script?`
**Decision:** `ScriptSelectorView` is a `Menu`/`Picker` bound to `selectedScriptID: Script.ID?` seeded from the launching tab (`Scripts` → selected id, `My Takes` deep link nil, Studio CTA → last-selected via `@AppStorage("lastScriptID")`). On change, swap `PrompterView` input string and update `selectedScriptID` storage; no session restart. “No script” option sets binding to nil and shows placeholder prompter text.
**Rationale:** Minimal state; works with existing `PrompterView` which is already pure `text` input. Persists user intent across launches.
**Alternative:** Pass `Script` object directly — rejected, breaks when script deleted; ID lookup with fallback `ContentUnavailableView` is safer.

### 5. Settings bottom sheet (not inline tray)
**Decision:** `StudioSettingsSheet` presented via `.sheet(isPresented:)` with `detents = [.medium, .large]` and `dragIndicator(.visible)`. Contents: resolution `Picker`, frame rate `Picker`, HDR toggle (disabled if `!device.formats.contains(where: \.isVideoHDRSupported)` with caption), mirror toggle, countdown toggle, aspect `Picker`; unsupported res/fps combos disabled with explanatory `Text`. Sheet binds directly to same `@AppStorage` + live `resolution`/`frameRate` state that `StudioView` already watches via `onChange` → `await captureService.configure`.
**Rationale:** Reuses existing `CaptureService.configure` live-reconfig path; sheet does not own capture state, so dismiss does not deallocate session. Detents satisfy “bottom sheet” spec without custom UI.
**Alternative:** Custom bottom sheet modifier — unnecessary until sheet needs grabber-customization beyond detents.

### 6. Review edit/delete/export from My Takes
**Decision:** `MyTakesView` row swipe actions: **Delete** (destructive → remove `Take` + file + `modelContext.delete`) and **Edit** → push `ReviewView(take:)` with an `editMode` that allows re-trim + LUT change → `ExportService` re-exports to a *new* temp file, then on “Save as New Take” inserts a new `Take` (preserving original) or “Replace” overwrites `relativeFilePath` atomically. Export/Share already in `ReviewView`; My Takes just routes there.
**Rationale:** Keeps single source of truth for export; avoids duplicating `AVAssetExportSession` logic.
**Alternative:** Duplicate export UI in My Takes — rejected, drift.

## Risks / Trade-offs

- **Tab shell deallocates tab stacks on switch if not retained** → Mitigate: store three `NavigationPath` values in `RootTabView` `@State`, not inside tab views; use `SceneStorage` for selected tab.
- **`pauseRecording` file is finalized only on `stopRecording`; interruption while paused could lose file** → Mitigate: observe `AVAudioSession.interruptionNotification` + `scenePhase == .background` while paused → call `stopRecording` to finalize immediately.
- **Sheet-driven `CaptureService.configure` while recording will interrupt file** → Mitigate: disable resolution/fps/HDR controls while `isRecording || isPaused` with banner “Stop recording to change camera format”; allow only mirror/aspect/countdown toggles live.
- **Script selector change mid-recording changes prompter but not burned-in metadata** → Mitigate: store `scriptID` on the final `Take` at Stop time (use selector’s current value), document that midpoint script swap is prompter-only.
- **Full-screen cover retains camera session after dismiss → battery** → Mitigate: `StudioView.onDisappear` calls `captureService.stopSession()` + `audioService.stopMetering()` as already implemented.

## Migration Plan

1. Add `RootTabView` + `MyTakesView` + `ProfileView` + `StudioSettingsSheet` + `ScriptSelectorView` + pause extension to `CaptureService`; gate with feature flag `ENABLE_TAB_SHELL`.
2. Rewire `ContentView` to render `RootTabView` when flag enabled; keep old `NavigationStack` path for snapshot tests.
3. Implement pause/resume branch (primary = `pauseRecording` selector check, fallback = segment merge) + prompter freeze + Live Activity paused state.
4. Move `TweakTrayView` speed/font/opacity + aspect controls into sheet; leave temporary inline tray behind `#if !ENABLE_TAB_SHELL` until verified.
5. Wire My Takes search/grouping/empty states + Review edit flow.
6. Manual device QA: tab state retention, Studio cover lifecycle, script switch, sheet disable-while-recording, pause/resume 3×, background while paused, My Takes edit/delete.

## Open Questions

- **Default tab on cold launch**: My Takes vs Scripts? Proposal says “you can see your previous takes”, implies My Takes first — confirm.
- **Pause file naming**: should paused-resumed recording produce one `Take` or multiple selectable takes? Spec says “pause functionality” singular — assume single merged take.
- **Profile scope**: placeholder only or must include editable preferences (resolution defaults etc.) now? Assume read-only links to Settings + version.
- **HDR availability per format**: per-device `activeFormat.isVideoHDRSupported` — should unsupported combo show as disabled or hide the toggle? Current plan: disabled with caption.
