//
//  LegalDocuments.swift
//  OneTake
//
//  Owns: Terms & Privacy content slots — bundled markdown + upstream URLs.
//  Why: Legal copy belongs to the owner, not the codebase: URLs and bundled
//  files are single constants to replace, the UI reads only through here, and
//  `#warning` blocks a submission build until real content lands.
//  See: openspec/changes/onboarding-terms-paywall/specs/legal-acceptance/spec.md
//
import Foundation

// Legal URLs are optional — bundled markdown is the fallback; see docs/STORE_SETUP.md §3.
enum LegalDocuments {
    /// Public Terms of Service URL — hosted at onetake.blinkeye.app
    static let termsURLString = "https://onetake.blinkeye.app/terms"

    /// Public Privacy Policy URL — hosted at onetake.blinkeye.app
    static let privacyURLString = "https://onetake.blinkeye.app/privacy"

    /// Bump to force re-acceptance when the documents change.
    static let currentVersion = 1

    static var termsURL: URL? {
        URL(string: termsURLString).flatMap { $0.scheme != nil ? $0 : nil }
    }

    static var privacyURL: URL? {
        URL(string: privacyURLString).flatMap { $0.scheme != nil ? $0 : nil }
    }

    static func bundledText(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "" }
        return text
    }
}
