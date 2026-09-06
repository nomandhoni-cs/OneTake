//
//  RecordingActivityService.swift
//  OneTake
//

import ActivityKit
import Foundation

@MainActor
final class RecordingActivityService {
    private var activity: Activity<RecordingAttributes>?
    private var updateTask: Task<Void, Never>?

    var isActive: Bool {
        activity != nil
    }

    func start(scriptTitle: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            debugPrint("[LiveActivity] activities not enabled, fallback to in-app HUD")
            return
        }
        // Ensure single activity
        Task { await end() }

        let attrs = RecordingAttributes(scriptTitle: scriptTitle)
        let initial = RecordingAttributes.ContentState(elapsedSeconds: 0, audioLevel: 0, isRecording: true)
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: initial, staleDate: nil),
                pushType: nil
            )
            debugPrint("[LiveActivity] started id=\(activity?.id ?? "?")")
        } catch {
            debugPrint("[LiveActivity] request failed: \(error)")
        }
    }

    func update(elapsedSeconds: Int, audioLevel: Float) {
        guard let activity else { return }
        // Throttle: caller should ensure 1 Hz; service does not re-throttle.
        let state = RecordingAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            audioLevel: audioLevel,
            isRecording: true
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    func endSync() {
        Task { await end() }
    }
}
