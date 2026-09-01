# Getting Started — OneTake

> Start at [`AGENTS.md`](../AGENTS.md) → [`ARCHITECTURE.md`](ARCHITECTURE.md) → [`CODEMAP.md`](CODEMAP.md).

## Prerequisites

- **macOS 26** (Tahoe) with **Xcode 17** (26.5 SDK) — `xcodebuild -version`
- **iOS 18.6+** deployment target (project uses 26.5 SDK, Liquid Glass on 26)
- No CocoaPods/SPM deps — pure SwiftData/SwiftUI/AVFoundation
- Tools (optional but recommended): `brew install swiftlint swiftformat`

```bash
swiftlint version # 0.65.1
swiftformat --version # 0.63.0
```

## Clone & Open

```bash
git clone <repo-url> OneTake && cd OneTake
open OneTake.xcodeproj
```

Select **OneTake** scheme, **iPhone 17 Pro** simulator (or iPad Pro 11-inch (M5)), `Cmd+R`.

## Build from CLI

```bash
# Build (iPhone)
xcodebuild -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/OneTakeDD build

# Build (iPad)
xcodebuild -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath /tmp/OneTakeDD-iPad build
```

## Run Tests

```bash
# Unit tests only (fast, ~0.5s for Blade thumbnails)
xcodebuild test -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:OneTakeTests

# All tests (includes UI tests — needs booted simulator)
xcodebuild test -project OneTake.xcodeproj -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Current: **33 tests passed** — `BladeEditingTests` (7), `ScriptCategoryTests` (8), `PersistenceTests`, `CadenceTests`, `TrimExportTests`, `TakesLibraryTests`, plus 1 UI test (`CategoryUITests`).

## Lint & Format

```bash
swiftlint lint                    # 0 errors, ~152 warnings (see LINT_REPORT.md)
swiftlint --fix                   # autocorrect whitespace, trailing commas, etc.
swiftformat .                     # 4-space indent, 140 maxwidth, alpha imports
```

Config: `.swiftlint.yml` (opt-in `force_unwrapping`/`force_cast`/`force_try` as error, `file_length` 400/600, `type_body_length` 300/400) + `.swiftformat` (5.9, `maxwidth 140`).

Pre-commit: run both before pushing; CI runs `xcodebuild test` + `swiftlint`.

## Simulator Tips

- **App icon:** `OneTake/Resources/logo.icon` (Icon Composer, 3 SVGs + `icon.json`, Liquid Glass light/dark/tinted variants). `ASSETCATALOG_COMPILER_APPICON_NAME = logo`.
- **First launch:** `My Takes` tab is empty → "Record your first take" CTA. `Scripts` tab → "Create First Script".
- **Categories:** In `Scripts`, tap ellipsis → Manage Categories or create from editor's category picker ("New Category…"). Chips filter the list; long-press row → Move to Category.
- **Blade:** In `Review` (tap a take → Review), `TrimScrubberView` shows cut dividers + playhead; **Blade** splits at playhead (or mid), **Delete Segment** removes selected, **Undo Blade** reverts. Trim changes prune out-of-range cuts.
- **LUTs:** `Review` → Color section shows **swatches** (40×24, CoreImage `colorCube` thumbnails, cached). Tap to select; Natural = neutral gray.
- **Studio as tab:** Bottom bar is 4 tabs (My Takes / Scripts / Studio / Profile) — no floating button. Studio publishes `studioIsRecording` via `AppStorage`; leaving mid-recording shows `confirmationDialog`.
- **Reset store:** Delete app from simulator or `xcrun simctl uninstall booted com.nomandhoni.OneTake`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No such file .../logo.icon` | Ensure `OneTake/Resources/logo.icon` exists; `PBXFileSystemSynchronizedRootGroup` auto-syncs it |
| `SwiftLint not installed` warning in Xcode | `brew install swiftlint` (build still succeeds) |
| `Cannot find 'ScriptCategory' in scope` in preview | Update `modelContainer(for: [Script.self, Take.self, ScriptCategory.self])` — 17 call sites |
| `File length` lint error | See `ARCHITECTURE.md` §11 — tracked tech debt, split planned |
| `AVAssetExportSession` fails on simulator | Check `take.fileURL` exists; `TrimScrubberView` 1s min duration |

## Next Steps

- Read `docs/ARCHITECTURE.md` for the full layer diagram and data flow.
- Read `docs/CODEMAP.md` for file-by-file ownership.
- Run `openspec list --json` and `openspec status --change unified-tabs-lut-preview-blade-trim` to see the spec-driven workflow.
