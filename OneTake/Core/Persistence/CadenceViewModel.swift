//
//  CadenceViewModel.swift
//  OneTake
//

import Foundation
import Observation

/// Live word & cadence engine: converts word count into estimated speaking
/// duration at a 130 words-per-minute baseline, updated in real time while typing.
@Observable
@MainActor
final class CadenceViewModel {
    static let wordsPerMinute: Double = 130

    // MARK: - State

    private(set) var wordCount: Int = 0
    private(set) var durationSeconds: Int = 0

    // MARK: - API

    /// Synchronous update — no user-visible debounce (spec: cadence-engine).
    func update(body: String) {
        wordCount = Self.wordCount(in: body)
        durationSeconds = Self.durationSeconds(wordCount: wordCount)
    }

    // MARK: - Pure math (testable)

    nonisolated static func wordCount(in body: String) -> Int {
        body.split(whereSeparator: { $0.isWhitespace }).count
    }

    nonisolated static func durationSeconds(wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        let seconds = Double(wordCount) / wordsPerMinute * 60
        return Int(seconds.rounded())
    }

    nonisolated static func formattedDuration(wordCount: Int) -> String {
        let total = durationSeconds(wordCount: wordCount)
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
