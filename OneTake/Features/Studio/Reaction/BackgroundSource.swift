//
//  BackgroundSource.swift
//  OneTake
//
//  Owns: Reaction background media — Photos picking, DRM rejection, and
//  `AVPlayer` playback for the performer to react to.
//  Why: One object owns the BG lifecycle (pick → validate → play) while the
//  export job reads frames deterministically from the file via its own
//  `AVAssetReader`; the preview renders this player's layer directly.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Validated background media ready for compositing.
struct BackgroundMedia {
    enum Kind {
        case video
        case image
    }

    let kind: Kind
    let localID: String?
    /// Local file URL for video (copied from the picker security scope).
    let videoURL: URL?
    /// Decoded image for photo backgrounds.
    let image: UIImage?

    var isVideo: Bool {
        kind == .video
    }
}

/// Errors surfaced when a picked clip cannot be used.
enum BackgroundSourceError: LocalizedError {
    case protectedContent
    case unreadable
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .protectedContent:
            "This video is protected and can't be used as a background. Please pick another clip."
        case .unreadable:
            "This media couldn't be loaded. Please pick another photo or video."
        case .unsupportedType:
            "Only photos and videos can be used as backgrounds."
        }
    }
}

/// Drives BG playback for preview and recording.
///
/// - Video: looping `AVPlayer` (looping pauses while `loopEnabled` is false so
///   the recorded camera-to-BG timeline mapping stays linear for export).
/// - Photo: held statically; the preview renders `media.image` directly.
@Observable
final class BackgroundSource {
    private(set) var media: BackgroundMedia?
    private(set) var isPlaying = false

    /// When false, the video holds its last frame at the end instead of
    /// looping (used during recording for a linear export timeline).
    var loopEnabled = true

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    /// Player for the preview layer. Nil for photo backgrounds.
    var previewPlayer: AVPlayer? {
        player
    }

    /// BG monitor volume 0...1, driven by the owner's volume slider.
    var liveVolume: Float = 0.4 {
        didSet {
            player?.volume = liveVolume
        }
    }

    var hasMedia: Bool {
        media != nil
    }

    var isVideo: Bool {
        media?.isVideo ?? false
    }

    /// Audio asset URL for the `AVAssetReader` recording path (video only).
    var audioSourceURL: URL? {
        guard media?.isVideo == true else { return nil }
        return media?.videoURL
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: - Media

    func setVideo(url: URL, localID: String?) async throws {
        try await Self.validateVideo(url: url)
        teardownPlayer()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = liveVolume
        newPlayer.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, loopEnabled else { return }
            restart()
        }
        player = newPlayer
        media = BackgroundMedia(kind: .video, localID: localID, videoURL: url, image: nil)
    }

    func setImage(_ image: UIImage, localID: String?) {
        teardownPlayer()
        media = BackgroundMedia(kind: .image, localID: localID, videoURL: nil, image: image)
    }

    func clear() {
        teardownPlayer()
        media = nil
        isPlaying = false
    }

    // MARK: - Transport

    func play() {
        guard media?.isVideo == true else { return }
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        if media?.isVideo == true {
            isPlaying = false
        }
    }

    func restart() {
        guard media?.isVideo == true else { return }
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
        isPlaying = true
    }

    // MARK: - Validation

    /// Rejects DRM/protected clips before they enter the pipeline.
    /// iOS 18.6 — uses `load(.hasProtectedContent)` / `load(.isPlayable)` per latest docs.
    static func validateVideo(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let hasProtected = await (try? asset.load(.hasProtectedContent)) ?? false
        if hasProtected {
            throw BackgroundSourceError.protectedContent
        }
        let playable = await (try? asset.load(.isPlayable)) ?? false
        if !playable {
            throw BackgroundSourceError.unreadable
        }
    }

    private func teardownPlayer() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player = nil
    }
}

/// Fullscreen BG video layer for the framing preview.
struct BackgroundPlayerView: UIViewRepresentable {
    var player: AVPlayer?

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass {
            AVPlayerLayer.self
        }

        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }
    }
}

/// Result of a Photos pick — a local file copy plus its library identifier.
struct PickedBackground {
    let fileURL: URL
    let isVideo: Bool
    let localID: String?
}

/// `PHPickerViewController` wrapper for BG photos/videos.
struct BackgroundPickerView: UIViewControllerRepresentable {
    var onPick: (Result<PickedBackground, Error>) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (Result<PickedBackground, Error>) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (Result<PickedBackground, Error>) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first else {
                onCancel()
                return
            }
            let provider = result.itemProvider
            let localID = result.assetIdentifier
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [onPick] url, _ in
                    guard let url else {
                        Task { @MainActor in onPick(.failure(BackgroundSourceError.unreadable)) }
                        return
                    }
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    try? FileManager.default.removeItem(at: dest)
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                    } catch {
                        Task { @MainActor in onPick(.failure(error)) }
                        return
                    }
                    Task {
                        do {
                            try await BackgroundSource.validateVideo(url: dest)
                            await MainActor.run {
                                onPick(.success(PickedBackground(fileURL: dest, isVideo: true, localID: localID)))
                            }
                        } catch {
                            await MainActor.run { onPick(.failure(error)) }
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [onPick] object, _ in
                    guard let image = object as? UIImage else {
                        Task { @MainActor in onPick(.failure(BackgroundSourceError.unreadable)) }
                        return
                    }
                    do {
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
                        guard let data = image.jpegData(compressionQuality: 0.92) else {
                            throw BackgroundSourceError.unreadable
                        }
                        try data.write(to: dest)
                        Task { @MainActor in
                            onPick(.success(PickedBackground(fileURL: dest, isVideo: false, localID: localID)))
                        }
                    } catch {
                        Task { @MainActor in onPick(.failure(error)) }
                    }
                }
            } else {
                onPick(.failure(BackgroundSourceError.unsupportedType))
            }
        }
    }
}
