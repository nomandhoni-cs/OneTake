//
//  VUMeterView.swift
//  OneTake
//

import SwiftUI

struct VUMeterView: View {
    var level: Float // -60..0 dBFS
    var normalized: Float {
        max(0, (level + 60) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0 ..< 20, id: \.self) { i in
                    let threshold = Float(i) / 20
                    let active = normalized > threshold
                    let isClip = i >= 18 && active
                    Rectangle()
                        .fill(active ? (isClip ? Color.red : (i > 14 ? Color.orange : Color.green)) : Color.white.opacity(0.18))
                        .frame(height: 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .animation(.easeOut(duration: 0.08), value: level)

            HStack {
                Text(String(format: "%.0f dB", level))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(level > -1 ? .red : .secondary)
                Spacer()
                if level > -1 {
                    Text("CLIP").font(.caption2.weight(.bold)).foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        VUMeterView(level: -6)
        VUMeterView(level: -30)
        VUMeterView(level: 0)
        VUMeterView(level: -60)
    }
    .padding()
    .background(Color.black)
}
