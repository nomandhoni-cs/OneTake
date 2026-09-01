//
//  CaptureService+Delegate.swift
//  OneTake
//
//  AVCaptureFileOutputRecordingDelegate — isolated in its own extension per
//  best practices (Protocol Extensions: split capabilities, keep files <400 lines).
//

import AVFoundation

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CaptureService: AVCaptureFileOutputRecordingDelegate {
    /// Called on an arbitrary queue when recording finishes (or fails).
    /// Uses `guard let` / `debugPrint` — no force unwraps.
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            debugPrint("[Capture] recording error: \(error)")
        } else {
            debugPrint("[Capture] finished: \(outputFileURL)")
        }
    }
}
