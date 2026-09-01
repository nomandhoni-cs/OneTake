//
//  CameraPreviewView.swift
//  OneTake
//

import AVFoundation
import SwiftUI

// swiftlint:disable force_try force_cast force_unwrapping

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isMirrored: Bool = true

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if let conn = uiView.videoPreviewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = isMirrored
        }
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        var session: AVCaptureSession? {
            get { videoPreviewLayer.session }
            set { videoPreviewLayer.session = newValue }
        }
    }
}

#if targetEnvironment(simulator)
    struct CameraPreviewPlaceholder: View {
        var body: some View {
            ZStack {
                Color.black
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Camera preview unavailable in Simulator")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Run on device to test capture")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }
#endif
// swiftlint:enable force_try force_cast force_unwrapping
