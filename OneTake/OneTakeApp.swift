//
//  OneTakeApp.swift
//  OneTake
//
//  Created by Abdullah Al Noman on 1/9/26.
//
//  App entry point — pure SwiftData + SwiftUI, zero third-party deps.
//
//  Best practices:
//  - `ModelContainer` is created once, on the main actor, from the versioned
//    schema (`OneTakeSchemaV1` + `OneTakeMigrationPlan`) with explicit
//    `ModelConfiguration(isStoredInMemoryOnly: false)` for persistence.
//  - No force-unwrap on container creation — `do/catch` with `fatalError` only
//    if the store is truly unrecoverable (e.g., migration failure).
//  - `WindowGroup` keeps body lightweight; no heavy work in `init`.
//  - To evolve models, see docs/PERSISTENCE.md (never edit a released version).
//
//  See: docs/ARCHITECTURE.md §3 (App Lifecycle) + AGENTS.md §3
import RevenueCat
import SwiftData
import SwiftUI

/// OneTake app — hosts the SwiftData container and root view.
@main
struct OneTakeApp: App {
    @State private var pro = ProEntitlementService()

    init() {
        // RevenueCat (SwiftUI doc, Option 1): configure once at launch when the
        // owner key is set; the service stays locked (non-pro) without it.
        if StoreIDs.isConfigured {
            Purchases.configure(withAPIKey: StoreIDs.revenueCatAPIKey)
            #if DEBUG
                Purchases.logLevel = .debug
            #endif
        } else {
            debugPrint("[Paywall] StoreIDs.revenueCatAPIKey is empty — Pro stays locked.")
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: OneTakeSchemaV1.self)

        do {
            // `groupContainer: .none` pins the store to the app container.
            // The default `.automatic` resolves into the App Group when the
            // entitlement exists, where first-launch creation hits
            // staging/sandbox quirks (errno 2 + recovery log spam).
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .none)
            return try ModelContainer(for: schema, migrationPlan: OneTakeMigrationPlan.self, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Brand accent (#195636) for every control app-wide.
                .tint(.appAccent)
                .environment(pro)
        }
        .modelContainer(sharedModelContainer)
    }
}
