//
//  Schema.swift
//  OneTake
//
//  Owns: The versioned SwiftData schema (V1 baseline) and migration plan.
//  Why: Explicit versions make future model changes safe — additive changes
//  migrate lightly and automatically, while renames/removals get a staged
//  mapping instead of a store reset or crash. Never edit a released version;
//  copy it forward and add a stage.
//  See: docs/PERSISTENCE.md + AGENTS.md §4
//
import Foundation
import SwiftData

/// V1 baseline — the exact model shapes (Script, Take, ScriptCategory)
/// shipped before versioning was introduced, including additive fields like
/// `Take.isReaction` / `backgroundAssetLocalID` and `Take.bladeCuts`.
enum OneTakeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Script.self, Take.self, ScriptCategory.self]
    }
}

/// Migration plan — maps each released schema version to the next.
/// Empty today: V1 is the only version, so fresh installs need no mapping.
/// When V2 lands, append it to `schemas` plus a `MigrationStage` here.
enum OneTakeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OneTakeSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
