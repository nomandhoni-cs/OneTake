# OneTake Persistence — Models, Store & Migrations

> Hub: [AGENTS.md](../AGENTS.md) §4 · App lifecycle: [ARCHITECTURE.md](ARCHITECTURE.md) §3–§5 · File map: [CODEMAP.md](CODEMAP.md)

Offline-first: SwiftData is the source of truth, `@Query` drives the UI, video
bytes live as files under Documents. This doc is the contract for evolving
stored data without breaking existing installs.

## 1. Model catalog

All models live in `OneTake/Core/Persistence/Script.swift`. Schema versions in
`OneTake/Core/Persistence/Schema.swift` (`OneTakeSchemaV1` + `OneTakeMigrationPlan`).

| Model | Key fields | Relationships / rules |
|---|---|---|
| `Script` | `id` (unique), `title`, `body`, `createdAt`, `updatedAt`, `category?` | Has many `takes` (cascade delete). Uncategorized scripts have `category == nil`. `displayTitle` falls back to "Untitled". |
| `Take` | `id` (unique), `scriptID`, `relativeFilePath`, `createdAt`, `duration`, `trimStart/trimDurationSeconds?`, `bladeCuts?`, `lutPreset`, `isReaction = false`, `backgroundAssetLocalID?` | Optional `script` link (`scriptID` survives script deletion; UI falls back to "Freestyle / No script"). |
| `ScriptCategory` | `id` (unique), `name`, `symbolName`, `createdAt` | Has many `scripts` (nullify on delete — scripts survive). |
| `LUTPreset` (enum) | `natural`, `warm_studio`, `cinematic_contrast`, `clean_monochrome` | Raw strings persisted in `Take.lutPreset`; `natural` means identity (filter skipped). Backed by 64³ `.cube` files in `Resources/`. |

Invariants to preserve:
- `Take.relativeFilePath` is relative to Documents (survives container moves across app updates); always resolve via `Take.fileURL`, never hardcode absolute paths.
- Every stored property needs a default or Optional — that is what makes migrations lightweight (see §3).
- No force unwraps on model reads; deleted-script and missing-file fallbacks must keep working (covered by `BladeEditingTests`, `ReactionModelTests`).

## 2. Where bytes live

- SwiftData store: explicit `default.store` URL in the app container's Application Support (pinned in `OneTakeApp` — never the shared App Group container, whose first-launch staging causes sandbox/recovery noise).
- Video files: `Documents/Takes/<uuid>.mp4` (`ExportService.takesDirectory()`); temp/segments cleaned after merge/export.
- Picker copies: `FileManager.temporaryDirectory` (BG media); safe to purge — originals stay in Photos.

## 3. Migration rules — will it break?

The app opens the store through `OneTakeMigrationPlan`. Two cases:

**Additive (safe, automatic):** new Optional property, or non-Optional with a
default value; new model; new relationship as Optional. SwiftData migrates
lightly with no code. Worked example: `Take.isReaction: Bool = false` and
`backgroundAssetLocalID: String?` shipped with zero migration code — old takes
read as non-reaction.

**Destructive (needs a staged plan):** rename, remove, retype, non-Optional
without default, relationship delete-rule/cardinality change. These NEED a new
schema version or the store fails to open (fatalError in `OneTakeApp`).

## 4. Checklist — adding a field (the common case)

1. Add the property with a default (`= false`) or as Optional.
2. Add a defaulted init param; keep existing call sites compiling untouched.
3. Confirm the change is additive per §3 — if yes, no schema change needed.
4. Add/extend a round-trip test (`*ModelTests`, `BladeEditingTests`).
5. Update the catalog table above if user-visible.
6. Device-test the upgrade: install the old build, create data, install the new build, verify data + app launch.

## 5. Playbook — destructive change (new version)

1. Freeze the current version (never edit `OneTakeSchemaV1` after release).
2. Add `OneTakeSchemaV2` (copy models forward with the breaking change applied;
   for renames, duplicate the model type so V1 and V2 can coexist).
3. Append V2 to `OneTakeMigrationPlan.schemas` and add a `MigrationStage`:
   `MigrationStage.lightweight(fromVersion: V1, toVersion: V2)` for renames the
   engine can infer, or `.custom(...)` with explicit mapping code.
4. Bump `CFBundleVersion`; test the upgrade path on device per §4.6.
5. Record the version + reason in this doc's changelog below.

## Changelog

- **V1 (1, 0, 0)** — baseline: Script, Take (incl. `bladeCuts`, `isReaction`, `backgroundAssetLocalID`), ScriptCategory. No stages.
