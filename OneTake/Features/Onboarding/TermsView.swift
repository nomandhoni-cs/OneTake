//
//  TermsView.swift
//  OneTake
//
//  Owns: Terms & Privacy presentation + acceptance.
//  Why: Legal acceptance must be timestamped and re-readable: `accept` mode
//  (onboarding gate) surfaces a summary with on-demand bottom sheets, `readOnly`
//  mode (Profile) renders full documents inline. Documents are markdown — a
//  polished block renderer (headings, bullets, bold) replaces the old single-
//  font Text so the copy scans instead of reading as "garbage".
//  See: openspec/specs/legal-acceptance/spec.md
//
import SwiftUI

/// Terms & Privacy screen — blocking gate or quiet reference.
struct TermsView: View {
    enum Mode {
        /// Compact onboarding gate — the caller now owns the fixed Agree CTA
        /// (bottom bar) so it never scrolls away. The closure is kept for
        /// backwards-compat and is unused internally; parents call their own
        /// `agree` action for the fixed bar.
        case accept(onAgree: () -> Void)
        case readOnly
    }

    let mode: Mode

    @State private var sheet: LegalSheetKind?

    var body: some View {
        Group {
            switch mode {
            case .accept:
                acceptContent
            case .readOnly:
                readOnlyContent
            }
        }
        .sheet(item: $sheet) { kind in
            LegalSheetContent(kind: kind)
        }
    }

    // MARK: - Accept (onboarding) — summary + on-demand readers, no inline wall

    private var acceptContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LegalSummaryCard()
                previewCards
                footnote
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 8)
        }
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("Terms & Privacy")
                .font(.title2.weight(.bold))
            Text("Please review the summary. You can open the full documents any time before you agree.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var previewCards: some View {
        HStack(spacing: 12) {
            LegalPreviewCard(
                title: "Terms of Service",
                icon: "doc.text",
                detail: "10 sections · ~4 min",
                action: { sheet = .terms }
            )
            .accessibilityLabel("View Terms of Service")
            LegalPreviewCard(
                title: "Privacy Policy",
                icon: "hand.raised",
                detail: "8 sections · ~3 min",
                action: { sheet = .privacy }
            )
            .accessibilityLabel("View Privacy Policy")
        }
    }

    private var footnote: some View {
        Text("The full documents are also available anytime from Profile → Terms & Privacy.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Full documents also available from Profile, Terms and Privacy.")
    }

    // MARK: - Read-only (Profile) — full inline documents, polished typography

    private var readOnlyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LegalSummaryCard()
                LegalDocumentCard(
                    title: "Terms of Service",
                    markdown: LegalDocuments.bundledText(named: "Terms"),
                    url: LegalDocuments.termsURL
                )
                LegalDocumentCard(
                    title: "Privacy Policy",
                    markdown: LegalDocuments.bundledText(named: "Privacy"),
                    url: LegalDocuments.privacyURL
                )
            }
            .padding()
        }
        .navigationTitle("Terms & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cards & markdown

/// Bottom-sheet kind — also used by onboarding's fixed bottom bar.
enum LegalSheetKind: String, Identifiable {
    case terms, privacy
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Privacy Policy"
        }
    }

    var markdown: String {
        switch self {
        case .terms: LegalDocuments.bundledText(named: "Terms")
        case .privacy: LegalDocuments.bundledText(named: "Privacy")
        }
    }

    var url: URL? {
        switch self {
        case .terms: LegalDocuments.termsURL
        case .privacy: LegalDocuments.privacyURL
        }
    }
}

/// One legal document — polished block renderer, not a single-font Text.
struct LegalDocumentCard: View {
    let title: String
    let markdown: String
    let url: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let url {
                    Link("Open online", destination: url)
                        .font(.subheadline.weight(.medium))
                        .accessibilityLabel("Open \(title) online")
                }
            }
            Divider().opacity(0.5)
            if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("The \(title.lowercased()) text is being finalized and will appear here before release.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                FormattedMarkdownView(markdown: markdown)
            }
        }
        .padding(16)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Compact preview card that opens a bottom sheet — used in the onboarding gate.
struct LegalPreviewCard: View {
    let title: String
    let icon: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("View").font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.appAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityAddTraits(.isButton)
    }
}

/// Block-based markdown renderer: headings, bullets, and body each get their
/// own typography so the document scans instead of presenting as a flat grey
/// wall. Inline bold/italic/links are preserved via AttributedString.
struct FormattedMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .tint(Color.appAccent)
        .textSelection(.enabled)
    }

    private var blocks: [String] {
        let raw = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // Region form, not `disable:next`: swiftformat hoists `@ViewBuilder` above
    // the declaration, which would push a `:next` directive off its target.
    // swiftlint:disable avoid_helper_func_view
    @ViewBuilder
    private func blockView(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("# ") {
            let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            inlineText(content, font: .title3.weight(.bold), color: .primary)
        } else if trimmed.hasPrefix("## ") {
            let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            inlineText(content, font: .headline, color: .primary)
                .padding(.top, 4)
        } else if trimmed.hasPrefix("### ") {
            let content = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            inlineText(content, font: .subheadline.weight(.semibold), color: .primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") || trimmed.hasPrefix("___") {
            Divider().padding(.vertical, 4)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            bulletGroup(trimmed)
        } else if isNumberedList(trimmed) {
            numberedGroup(trimmed)
        } else if trimmed.hasPrefix("> ") {
            let content = String(trimmed.dropFirst(2))
            inlineText(content, font: .body, color: .secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(Color.primary.opacity(0.15)).frame(width: 3) }
                .padding(.leading, 2)
        } else {
            inlineText(trimmed, font: .body, color: Color.primary.opacity(0.88))
        }
    }

    private func bulletGroup(_ raw: String) -> some View {
        let lines = raw.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                let content = strippedBullet(t)
                Group {
                    if content.isEmpty {
                        EmptyView()
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Color.secondary).frame(width: 5, height: 5).padding(.top, 8)
                            inlineText(content, font: .body, color: Color.primary.opacity(0.88))
                        }
                    }
                }
            }
        }
    }

    private func strippedBullet(_ t: String) -> String {
        if t.hasPrefix("- ") {
            return String(t.dropFirst(2))
        }
        if t.hasPrefix("* ") {
            return String(t.dropFirst(2))
        }
        if t.hasPrefix("• ") {
            return String(t.dropFirst(2))
        }
        return t
    }

    private func numberedGroup(_ raw: String) -> some View {
        let lines = raw.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                let content = strippedNumbered(t)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(idx + 1).").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                    inlineText(content, font: .body, color: Color.primary.opacity(0.88))
                }
            }
        }
    }

    private func strippedNumbered(_ t: String) -> String {
        guard let dot = t.firstIndex(of: ".") else { return t }
        let after = t.index(after: dot)
        return after < t.endIndex ? String(t[after...]).trimmingCharacters(in: .whitespaces) : t
    }

    private func isNumberedList(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isNumber else { return false }
        return t.contains(". ")
    }

    private func inlineText(_ string: String, font: Font, color: Color) -> some View {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let attr = try? AttributedString(
            markdown: trimmed,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr).font(font).foregroundStyle(color).lineSpacing(2)
        } else {
            return Text(trimmed).font(font).foregroundStyle(color).lineSpacing(2)
        }
    }
    // swiftlint:enable avoid_helper_func_view
}

/// Bottom sheet reader — medium + large detents, drag indicator, polished markdown.
struct LegalSheetContent: View {
    let kind: LegalSheetKind
    // swiftlint:disable:next attributes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(kind.title, systemImage: kind == .terms ? "doc.text" : "hand.raised")
                            .font(.headline)
                        Spacer()
                        if let url = kind.url {
                            Link("Open online", destination: url).font(.subheadline.weight(.medium))
                        }
                    }
                    Divider()
                    if kind.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("The \(kind.title.lowercased()) text is being finalized and will appear here before release.")
                            .font(.body).foregroundStyle(.secondary)
                    } else {
                        FormattedMarkdownView(markdown: kind.markdown)
                    }
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
}

/// Plain-language key points above the full text.
struct LegalSummaryCard: View {
    private let points: [(icon: String, text: String)] = [
        ("lock.shield.fill", "Private by design — scripts and videos stay on your device."),
        ("video.fill", "Your videos are yours. Get consent before recording others."),
        ("crown.fill", "Pro: $12.99/yr with a 7-day trial, $1.99/mo, or $39.99 lifetime. Cancel anytime in Settings."),
        ("arrow.clockwise", "Restore Purchases brings Pro back on any of your devices."),
        ("doc.text.fill", "The full terms and privacy policy are one tap away — please read them before you agree."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The short version")
                .font(.headline)
            ForEach(points, id: \.text) { point in
                Label {
                    Text(point.text).font(.subheadline)
                } icon: {
                    Image(systemName: point.icon).foregroundStyle(Color.appAccent)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityLabel(
            "Summary: private by design, your videos are yours, Pro plans with trial, restore on any device, full text available."
        )
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
