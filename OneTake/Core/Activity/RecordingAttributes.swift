//
//  RecordingAttributes.swift
//  OneTake
//

import ActivityKit
import SwiftUI

struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var audioLevel: Float // 0..1
        var isRecording: Bool
    }

    var scriptTitle: String
}

#if canImport(WidgetKit)
    import WidgetKit

    @available(iOS 16.1, *)

    // swiftlint:disable:next attributes
    struct RecordingLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: RecordingAttributes.self) { context in
                // Lock Screen / Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("REC \(Self.format(seconds: context.state.elapsedSeconds))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(context.attributes.scriptTitle.isEmpty ? "OneTake" : context.attributes.scriptTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: context.state.audioLevel)
                        .tint(context.state.audioLevel > 0.95 ? .red : .blue)
                    Text(context.state.isRecording ? "Recording" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 10, height: 10)
                            Text(Self.format(seconds: context.state.elapsedSeconds))
                                .font(.headline.monospacedDigit())
                        }
                        .padding(.leading, 4)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        ProgressView(value: context.state.audioLevel)
                            .frame(width: 40)
                            .tint(context.state.audioLevel > 0.95 ? .red : .blue)
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        HStack {
                            Text(context.attributes.scriptTitle.isEmpty ? "Recording" : context.attributes.scriptTitle)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(context.state.isRecording ? "● REC" : "Paused")
                                .font(.caption2.bold())
                                .foregroundStyle(context.state.isRecording ? .red : .secondary)
                        }
                    }
                } compactLeading: {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                } compactTrailing: {
                    Text(Self.format(seconds: context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 42)
                } minimal: {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
            }
        }

        static func format(seconds: Int) -> String {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%02d:%02d", m, s)
        }
    }
#endif
