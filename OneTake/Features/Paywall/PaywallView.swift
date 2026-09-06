//
//  PaywallView.swift
//  OneTake
//
//  Owns: The Pro offer wall — packages, purchase, restore, legal footer.
//  Why: One wall serves onboarding, entitlement gates, and Profile: trial copy
//  derives from the store discount object (never constants), errors map to
//  human strings, and the footer carries the auto-renewal disclosures App
//  Review requires (price, duration, trial, cancel path, legal links).
//  See: docs/PRICING.md + openspec/changes/onboarding-terms-paywall/specs/paywall/spec.md
//
import SwiftUI

/// Pro paywall. `onUnlocked` fires after purchase/restore flips `isPro`.
struct PaywallView: View {
    @Environment(ProEntitlementService.self)
    private var pro
    @Environment(\.dismiss)
    private var dismiss

    /// Shows an X (sheet use). When false the host owns dismissal/skip.
    var showsClose = false
    var onUnlocked: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if pro.isLoadingPackages, pro.packages.isEmpty {
                    ProgressView().padding(.vertical, 24)
                } else if pro.packages.isEmpty {
                    ContentUnavailableView {
                        Label("Plans unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Retry") { Task { await pro.refresh() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    packageList
                    continueButton
                    restoreButton
                }
                if let error = pro.lastError {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Purchase error: \(error.localizedDescription)")
                }
                footer
            }
            .padding()
        }
        .navigationTitle("OneTake Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close paywall")
                }
            }
        }
        .task { await pro.refresh() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.fill.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text("OneTake Pro")
                .font(.largeTitle.weight(.bold))
            Text("Record, grade, and export without limits — every studio, all 10 LUTs, 4K export.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var packageList: some View {
        VStack(spacing: 8) {
            ForEach(pro.packages) { package in
                let isSelected = package.id == pro.selectedPackage?.id
                Button { pro.select(package) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let trial = PaywallCopy.trialLine(for: package.trial) {
                                Text(trial)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.appAccent)
                            } else {
                                Text(package.priceString)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appAccent)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        isSelected ? Color.appAccent.opacity(0.12) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.appAccent : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(package.title), \(PaywallCopy.trialLine(for: package.trial) ?? package.priceString)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    private var continueButton: some View {
        Button(continueTitle) {
            Task {
                if await pro.purchaseSelected() {
                    onUnlocked?()
                    dismiss()
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(pro.selectedPackage == nil || pro.isPurchasing)
        .accessibilityLabel(continueTitle)
    }

    private var continueTitle: String {
        if pro.isPurchasing {
            return "Processing…"
        }
        guard let selected = pro.selectedPackage else {
            return "Continue"
        }
        if selected.trial != nil {
            return "Start Free Trial"
        }
        return switch selected.kind {
        case .lifetime: "Buy Lifetime"
        case .monthly: "Subscribe Monthly"
        case .annual: "Subscribe Annual"
        case .other: "Continue"
        }
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                if await pro.restore() {
                    onUnlocked?()
                    dismiss()
                }
            }
        }
        .font(.subheadline)
        .disabled(pro.isPurchasing)
        .accessibilityLabel("Restore purchases")
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // Single localized string by law (§7 beats line length — App Review
            // requires this disclosure whole on auto-renewable offer walls).
            Text(
                // swiftlint:disable:next line_length
                "Payment is charged at confirmation. Subscriptions auto-renew unless cancelled at least 24 hours before the period ends. Manage or cancel anytime in Settings → Apple ID → Subscriptions."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            HStack(spacing: 20) {
                if let terms = LegalDocuments.termsURL {
                    Link("Terms of Service", destination: terms).font(.caption)
                }
                if let privacy = LegalDocuments.privacyURL {
                    Link("Privacy Policy", destination: privacy).font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Locked") {
    NavigationStack {
        PaywallView(showsClose: true)
            .environment(ProEntitlementService.previewLocked)
    }
}

#Preview("Unlocked") {
    NavigationStack {
        PaywallView()
            .environment(ProEntitlementService.previewUnlocked)
    }
}
