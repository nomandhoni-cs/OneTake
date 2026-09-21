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
    @State private var pro: ProEntitlementService

    init() {
        // RevenueCat (SwiftUI doc, Option 1): configure once at launch when the
        // owner key is set; the service stays locked (non-pro) without it.
        // Order matters: `ProEntitlementService` attaches the `customerInfoStream`
        // listener in its init and bails when `Purchases.isConfigured` is false,
        // so it must be built *after* `configure` — hence the explicit `_pro`
        // assignment instead of a stored-property default (which Swift would
        // evaluate before this body runs).
        if StoreIDs.isConfigured {
            // `.info` (not `.debug`) in release: TestFlight/App Store builds print
            // the offering + StoreKit product-fetch outcome to the device console,
            // which is the only way to tell "no products from App Store Connect"
            // apart from a network fault on a real device.
            #if DEBUG
                Purchases.logLevel = .debug
            #else
                Purchases.logLevel = .info
            #endif
            Purchases.configure(withAPIKey: StoreIDs.revenueCatAPIKey)
        } else {
            debugPrint("[Paywall] StoreIDs.revenueCatAPIKey is empty — Pro stays locked.")
        }
        _pro = State(initialValue: ProEntitlementService())
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
