//
//  ProcessingView.swift
//  OneTake
//
//  Owns: Post-capture export progress UI — determinate bar with cancel.
//  Why: Capture-first trades instant files for an export wait; a calm,
//  cancellable progress screen makes the wait legible instead of a hang.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import SwiftUI

/// Export progress overlay. `progress` nil = preparing (indeterminate).
struct ProcessingView: View {
    var progress: Double?
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text("Processing reaction…")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Processing reaction")
                if let progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 220)
                        .accessibilityValue("\(Int(progress * 100)) percent")
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text("Cutout, background, and sound are being finished. You can cancel — your recording is kept.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityLabel("Cancel processing")
            }
            .padding(24)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    ProcessingView(progress: 0.42, onCancel: {})
        .background(Color.gray)
}
