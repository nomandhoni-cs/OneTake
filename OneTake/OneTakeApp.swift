//
//  OneTakeApp.swift
//  OneTake
//
//  Created by Abdullah Al Noman on 1/9/26.
//
//  App entry point — pure SwiftData + SwiftUI, zero third-party deps.
//
//  Best practices:
//  - `ModelContainer` is created once, on the main actor, via `Schema` with
//    explicit `ModelConfiguration(isStoredInMemoryOnly: false)` for persistence.
//  - No force-unwrap on container creation — `do/catch` with `fatalError` only
//    if the store is truly unrecoverable (e.g., migration failure).
//  - `WindowGroup` keeps body lightweight; no heavy work in `init`.
//
//  See: docs/ARCHITECTURE.md §3 (App Lifecycle) + AGENTS.md §3
import SwiftData
import SwiftUI

/// OneTake app — hosts the SwiftData container and root view.
@main
struct OneTakeApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Script.self,
            Take.self,
            ScriptCategory.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Brand accent (#195636) for every control app-wide.
                .tint(.appAccent)
        }
        .modelContainer(sharedModelContainer)
    }
}
