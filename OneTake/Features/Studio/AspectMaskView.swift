//
//  AspectMaskView.swift
//  OneTake
//

import SwiftUI

struct AspectMaskView: View {
    var ratio: AspectRatio
    @Namespace private var ns

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let (maskW, maskH): (CGFloat, CGFloat) = {
                switch ratio {
                case .wide: // 16:9
                    let mh = w * 9 / 16
                    return (w, mh)
                case .vertical: // 9:16
                    let mw = h * 9 / 16
                    return (mw, h)
                case .square: // 1:1
                    let s = min(w, h)
                    return (s, s)
                }
            }()

            ZStack {
                Color.black
                // Center cutout
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: maskW, height: maskH)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .matchedGeometryEffect(id: "mask-\(ratio.rawValue)", in: ns)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: ratio)
            .allowsHitTesting(false)
            .opacity(0.72)
        }
    }
}

struct AspectPickerView: View {
    @Binding var ratio: AspectRatio
    var body: some View {
        Picker("Aspect", selection: $ratio) {
            ForEach(AspectRatio.allCases) { r in
                Text(r.displayName).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }
}

#Preview {
    ZStack {
        Color.gray
        AspectMaskView(ratio: .vertical)
    }
    .frame(height: 400)
}
