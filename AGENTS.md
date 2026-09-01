# AGENTS.md — OneTake Contributor & Agent Handbook

> **Start here.** This file is the agent (and human) entry point. It links every doc, explains where code lives, and sets the maintainability contract (comments, lint, specs). Follow the links; keep them in sync.

## 1. Project in 30 Seconds

**OneTake** is an offline-first iOS teleprompter + camera: write scripts → read from a scrolling prompter while the front camera records → trim / blade-split / grade with 3D LUTs → save to Photos. 100% SwiftUI + SwiftData, no network, no third-party deps.

- **Stack:** Swift 5.9, SwiftUI (Observation), SwiftData, AVFoundation + CoreImage/Metal + AVKit + Photos
- **Deployment:** iOS 18.6+ (Liquid Glass on iOS 26), Xcode 17 (26.5 SDK)
- **Style:** HIG, 44pt targets, VoiceOver, `TabView(sidebarAdaptable)` Liquid Glass

**Repo is spec-driven** — see [`openspec/`](openspec/) and §6.

## 2. Documentation Map — Follow the Links

| Doc | What it answers | When to read |
|-----|-----------------|--------------|
| **[README.md](README.md)** | One-page overview, features, tech-stack table, quick start, status badges | First clone, or to link the project externally |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | **Deep dive:** layers, app lifecycle, navigation (4-tab), persistence (`Script`/`Take`/`ScriptCategory` + `bladeCuts`), features, `Core/*` services, theme, testing, OpenSpec | Before touching `RootTabView`, `Script.swift`, or `ExportService` |
| **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)** | Prerequisites, `open *.xcodeproj`, CLI `xcodebuild build/test`, `swiftlint`/`swiftformat`, simulator tips | Setup, running, troubleshooting |
| **[docs/CODEMAP.md](docs/CODEMAP.md)** | **File-by-file map:** `OneTake/` target, `OneTakeTests/`, `OneTakeUITests/`, `openspec/`, `OneTake.xcodeproj` | To find *where* a responsibility lives |
| **[docs/LINT_REPORT.md](docs/LINT_REPORT.md)** | Best-practice audit: current `0 violations`, before/after, auto-fix vs manual, remaining warnings plan | Before committing, or to understand lint config |
| **`openspec/specs/`** (7 canonical) | `audio-settings-intents`, `cadence-engine`, `capture-engine`, `live-recording-hud`, `prompter-studio`, `script-workspace`, `trim-color-export` | To understand *what* the system shall do |
| **`openspec/changes/`** (2) | `bottom-nav-studio-flow` (prior), `unified-tabs-lut-preview-blade-trim` (17 tasks, 4-tab + LUT swatches + blade) | To see *why/how* a feature was built |

> **Linking contract:** Every doc links back here; `README.md` links to `docs/`; `docs/ARCHITECTURE.md` §10 links to `openspec/`; `AGENTS.md` is the hub. If you add a doc, link it here and in `README.md`.

## 3. Architecture — Where Data Comes From

```
OneTakeApp (ModelContainer: Script, Take, ScriptCategory)
 → ContentView (ENABLE_TAB_SHELL → RootTabView | LegacyContentView)
   → RootTabView (unified 4-tab TabView: My Takes / Scripts / Studio / Profile)
     ├─ My Takes → MyTakesView (@Query takes + scripts, blade + grouped menus)
     ├─ Scripts → ScriptLibraryView (search + filter chips + sort, grouped by category)
     ├─ Studio  → StudioView (camera + PrompterView, @AppStorage studioIsRecording)
     └─ Profile → ProfileView
   Core/Persistence (Script.swift = models + LUTPreset)
   Core/Export (ExportService.exportTake → AVMutableComposition)
   Core/LUTs (LUTCubeLoader + LUTThumbnailProvider → LUTSwatchView)
```

- **Source of truth:** SwiftData `@Model`; `@Query` drives UI. `Take.relativeFilePath` survives container moves.
- **Navigation:** Per-tab `NavigationPath` (`takesPath`/`scriptsPath`/`studioPath`/`profilePath`) + `@SceneStorage("selectedTab")` + `Notification.Name.showStudio` → `selectedTab=.studio`.
- **Theme:** `AppTheme.swift` → `Color.appAccent` (`AccentColor` #195636) + `BrandSecondary` #FCCD03, `logo.icon` (Icon Composer).

Full diagram + data-flow (Script → Studio → Take → Review) in **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** §7.

## 4. Where Code Lives — Quick Finder

```
OneTake/OneTakeApp.swift              # @main, Schema, WindowGroup
OneTake/ContentView.swift             # ENABLE_TAB_SHELL, Route, ScriptLibraryView + ScriptRow
OneTake/RootTabView.swift             # AppTab (4 cases), RootTabView, ScriptsTab, StudioTab
OneTake/Core/Persistence/Script.swift # Script, ScriptCategory, Take (bladeCuts), LUTPreset
OneTake/Core/Theme/AppTheme.swift     # Color tokens
OneTake/Core/LUTs/LUTCubeLoader.swift + LUTThumbnailProvider.swift # .cube → CGImage 40×24
OneTake/Core/Export/ExportService.swift # passthrough / colorCube / composition
OneTake/Features/Studio/*             # StudioView, CaptureService, CameraPreviewView, PrompterView, etc.
OneTake/Features/Takes/MyTakesView.swift # Takes list + blade + grouped context menu
OneTake/Features/Review/*             # ReviewView (blade-aware player/trim/LUT/export), TrimScrubberView (blade UI)
OneTake/Features/Workspace/*          # ScriptEditorSheet, ScriptCategoryViews (kit)
OneTakeTests/*                        # BladeEditingTests, ScriptCategoryTests, etc.
```

Exhaustive table: **[docs/CODEMAP.md](docs/CODEMAP.md)**.

## 5. How to Work — Setup, Lint, Test, Spec

### Setup
```bash
git clone <repo> && cd OneTake
open OneTake.xcodeproj # OneTake scheme, iPhone 17 Pro, Cmd+R
brew install swiftlint swiftformat # optional but recommended
```

### Lint & Format (must pass before push)
```bash
swiftformat . && swiftlint --fix
swiftlint lint OneTake --quiet # expect 0 violations (see docs/LINT_REPORT.md)
swiftformat --lint .           # expect 0/40 require formatting
xcodebuild -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/OneTakeDD build
xcodebuild test -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OneTakeTests # 33 passed
```

Config: [`.swiftlint.yml`](.swiftlint.yml) (opt-in `force_unwrapping` etc., `file_length` 700/900, `type_body_length` 650/800, `function_body_length` 85/150) + [`.swiftformat`](.swiftformat) (4-space, 140 maxwidth). See **[docs/LINT_REPORT.md](docs/LINT_REPORT.md)** for triage.

### OpenSpec (spec-driven changes)
```bash
openspec list --json
openspec status --change <name> --json
openspec instructions <artifact> --change <name> --json
openspec validate --changes # expect 2 passed
```
Current: `unified-tabs-lut-preview-blade-trim` (17/17) + `bottom-nav-studio-flow` (21/22). New change: `openspec new change "<kebab>"` → proposal → design → specs → tasks → `openspec instructions apply`.

## 6. Maintainability Contract — Comments & Links

**Every file that owns a responsibility must have a meaningful header comment (3–6 lines) that:**

1. States *what* the file owns in one sentence.
2. States *why* the design choice (e.g., "bladeCuts as `[Double]?` not `Segment @Model` — additive lightweight migration").
3. Links to the doc that explains it (`See docs/ARCHITECTURE.md §5` or `openspec/specs/...`).

**Header template (copy):**
```swift
//
//  FileName.swift
//  OneTake
//
//  Owns: <one-line responsibility>
//  Why: <one-line design rationale>
//  See: docs/ARCHITECTURE.md §<n> + openspec/specs/<capability>/spec.md
//
```

**Linking contract:**
- `AGENTS.md` ↔ `README.md` ↔ `docs/*.md` ↔ `openspec/specs/*.md` must stay in sync. If you add a file, update `docs/CODEMAP.md`; if you add a feature, add a spec delta.
- Prefer `struct SmallView: View` over `func helper() -> some View` (see `.swiftlint.yml` `avoid_helper_func_view`).
- Prefer `@Observable` over `ObservableObject` (see custom rule).
- No `AnyView`, no force unwrap — `guard let` / `try?` + `// swiftlint:disable:next <rule>` with justification if unavoidable.

## 7. FAQ

**Q: Where do I add a new tab?** `RootTabView.swift` → `AppTab` + `Tab(...)` + `NavigationPath` + `selectedTab` handling. Keep HIG ≤5. See `docs/ARCHITECTURE.md` §4.

**Q: Where does a new model go?** `Core/Persistence/Script.swift` alongside `Script`/`Take`/`ScriptCategory`, add to `Schema([...])` in `OneTakeApp` and all 17 `modelContainer(for:)` previews/tests. See `docs/CODEMAP.md` → Core/Persistence.

**Q: How does blade export work?** `Take.bladeSegments()` → `ExportService.exportTake` builds `AVMutableComposition` + `AVVideoComposition` with `CIFilter.colorCube` only when needed. See `docs/ARCHITECTURE.md` §5 (Persistence) + §6 (Export).

---

*Last updated: 2026-09-02 — after `unified-tabs-lut-preview-blade-trim` + lint/docs pass. Keep this file short, linked, and honest.*
