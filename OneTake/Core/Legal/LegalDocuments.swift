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

#warning(
    "Owner content: paste Terms + Privacy URLs below (or leave empty), and replace Resources/*.md with real documents before submission."
)

/// Legal content source. Bundled files are the fallback; upstream URLs win
/// when set so web updates don't need an app release.
enum LegalDocuments {
    /// Public Terms of Service URL. Empty = bundled text only.
    static let termsURLString = ""

    /// Public Privacy Policy URL. Empty = bundled text only.
    static let privacyURLString = ""

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
