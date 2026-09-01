//
//  CountdownView.swift
//  OneTake
//

import SwiftUI

struct CountdownView: View {
    let count: Int // 3,2,1,0(GO)
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            // swiftlint:disable:next empty_count
            Text(count != 0 ? "\(count)" : "GO")
                .font(.system(size: 128, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 20)
                .transition(.scale.combined(with: .opacity))
                .id(count)
        }
    }
}
