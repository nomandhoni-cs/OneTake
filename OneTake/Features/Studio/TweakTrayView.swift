//
//  TweakTrayView.swift
//  OneTake
//

import SwiftUI

struct TweakTrayView: View {
    @Binding var speed: Double // 1.0–4.0
    @Binding var fontSize: Double // 18–36
    @Binding var opacity: Double // 0–0.8
    var onStepperTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            TweakRow(
                label: "Speed",
                valueLabel: String(format: "%.1f×", speed),
                sliderValue: $speed,
                range: 1.0 ... 4.0,
                step: 0.1,
                stepperRange: 1.0 ... 4.0,
                stepperStep: 0.1,
                onStepper: onStepperTap
            )
            TweakRow(
                label: "Font",
                valueLabel: String(format: "%.0f pt", fontSize),
                sliderValue: $fontSize,
                range: 18 ... 36,
                step: 1,
                stepperRange: 18 ... 36,
                stepperStep: 1,
                onStepper: onStepperTap
            )
            TweakRow(
                label: "Backdrop",
                valueLabel: String(format: "%.0f%%", opacity * 100),
                sliderValue: $opacity,
                range: 0 ... 0.8,
                step: 0.05,
                stepperRange: 0 ... 0.8,
                stepperStep: 0.05,
                onStepper: onStepperTap
            )
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TweakRow: View {
    let label: String
    let valueLabel: String
    @Binding var sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let stepperRange: ClosedRange<Double>
    let stepperStep: Double
    var onStepper: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(valueLabel).font(.caption.monospacedDigit()).foregroundStyle(.primary)
            }
            HStack(spacing: 10) {
                Button {
                    sliderValue = max(stepperRange.lowerBound, sliderValue - stepperStep)
                    onStepper?()
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease \(label)")

                Slider(value: $sliderValue, in: range, step: step)
                    .tint(.blue)

                Button {
                    sliderValue = min(stepperRange.upperBound, sliderValue + stepperStep)
                    onStepper?()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(label)")
            }
        }
    }
}

#Preview {
    @Previewable @State var s = 2.0
    @Previewable @State var f = 22.0
    @Previewable @State var o = 0.4
    TweakTrayView(speed: $s, fontSize: $f, opacity: $o)
        .padding()
}
