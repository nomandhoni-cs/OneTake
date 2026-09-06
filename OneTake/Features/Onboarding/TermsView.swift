//
//  TermsView.swift
//  OneTake
//
//  Owns: Terms & Privacy presentation + acceptance.
//  Why: Legal acceptance must be timestamped and re-readable: `accept` mode
//  (onboarding gate) records version + time, `readOnly` mode (Profile) just
//  renders. Bundled markdown with upstream links when the owner sets URLs.
//  See: openspec/changes/onboarding-terms-paywall/specs/legal-acceptance/spec.md
//
import SwiftUI

/// Terms & Privacy screen — blocking gate or quiet reference.
struct TermsView: View {
    enum Mode {
        /// Shows Agree; calls back with the acceptance instant.
        case accept(onAgree: () -> Void)
        case readOnly
    }

    let mode: Mode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LegalDocumentSection(
                    title: "Terms of Service",
                    bundled: LegalDocuments.bundledText(named: "Terms"),
                    url: LegalDocuments.termsURL
                )
                Divider()
                LegalDocumentSection(
                    title: "Privacy Policy",
                    bundled: LegalDocuments.bundledText(named: "Privacy"),
                    url: LegalDocuments.privacyURL
                )
                if case let .accept(onAgree) = mode {
                    Button("Agree & Continue") { onAgree() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Agree to Terms and Privacy Policy")
                }
            }
            .padding()
        }
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One legal document — struct (not a helper func) for view identity.
private struct LegalDocumentSection: View {
    let title: String
    let bundled: String
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let url {
                    Link("Open online", destination: url)
                        .font(.subheadline)
                        .accessibilityLabel("Open \(title) online")
                }
            }
            if let rendered = try? AttributedString(markdown: bundled), !bundled.isEmpty {
                Text(rendered).font(.body).foregroundStyle(.secondary)
            } else {
                Text("The \(title.lowercased()) text is being finalized and will appear here before release.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Accept") {
    NavigationStack {
        TermsView(mode: .accept(onAgree: {}))
    }
}

#Preview("Read-only") {
    NavigationStack {
        TermsView(mode: .readOnly)
    }
}
