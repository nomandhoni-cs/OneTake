//
//  OneTakeIntents.swift
//  OneTake
//

import AppIntents
import SwiftData
import SwiftUI

struct RecordScriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a Script in OneTake"
    static var description = IntentDescription("Open OneTake to record your script with the teleprompter.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Script Title", description: "Title of the script to record. Leave empty to open the library.", default: nil)

    // swiftlint:disable:next attributes
    var scriptTitle: String?

    @Parameter(title: "Script ID", description: "Optional script identifier.", default: nil)

    // swiftlint:disable:next attributes
    var scriptID: String?

    func perform() async throws -> some IntentResult {
        // App opening is handled by openAppWhenRun; optional validation via SwiftData could be added.
        // Fallback for missing script is handled in-app via navigation state.
        .result()
    }
}

struct OpenScriptIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Script"
    static var description = IntentDescription("Open a script by title.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Script Title")

    // swiftlint:disable:next attributes
    var scriptTitle: String

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct OneTakeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordScriptIntent(),
            phrases: [
                "Record a script in \(.applicationName)",
                "Record with \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Record Script",
            systemImageName: "video.fill"
        )
        AppShortcut(
            intent: OpenScriptIntent(),
            phrases: ["Open \(.applicationName) script"],
            shortTitle: "Open Script",
            systemImageName: "doc.text"
        )
    }
}
