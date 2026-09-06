//
//  PersonSegmenter.swift
//  OneTake
//
//  Owns: Person segmentation knowledge — request configuration (.accurate by
//  default, runtime pixel-format pick) and mask extraction for Vision.
//  Why: One place owns segmentation policy so the post-capture export job and
//  any future caller share quality/format decisions; the job owns the
//  `VNSequenceRequestHandler` lifetime for temporal consistency across frames.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/capture-first-reaction-pipeline/specs/reaction-post-processing/spec.md
//
import CoreImage
import Foundation
import Vision

/// Synchronous mask provider, implemented by `PersonSegmenter` and fakes.
protocol MaskProviding {
    /// Segments `pixelBuffer` with `handler` and returns the matte as
    /// `CIImage`, or `nil` when no person is found. Throws on inference error.
    func mask(from pixelBuffer: CVPixelBuffer, using handler: VNSequenceRequestHandler) throws -> CIImage?
}

/// ANE person-segmentation for offline export.
///
/// - Default quality `.accurate` (post-capture can afford it); switchable to
///   `.balanced` by the fps probe via `qualityLevel`.
/// - Mask pixel format picked at runtime from `supportedOutputPixelFormats()`.
final class PersonSegmenter: MaskProviding {
    var qualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate {
        didSet {
            request = Self.makeRequest(quality: qualityLevel)
        }
    }

    private var request = makeRequest(quality: .accurate)

    func mask(from pixelBuffer: CVPixelBuffer, using handler: VNSequenceRequestHandler) throws -> CIImage? {
        try handler.perform([request], on: pixelBuffer)
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    /// Best mask pixel format the device supports, falling back to 8-bit mono.
    static func bestPixelFormat() -> OSType {
        let probe = VNGeneratePersonSegmentationRequest()
        if let formats = try? probe.supportedOutputPixelFormats(), !formats.isEmpty {
            // Prefer compact single-component output when available.
            let mono = OSType(kCVPixelFormatType_OneComponent8)
            if formats.map({ OSType(truncating: $0) }).contains(mono) {
                return mono
            }
            return OSType(truncating: formats[0])
        }
        return OSType(kCVPixelFormatType_OneComponent8)
    }

    private static func makeRequest(quality: VNGeneratePersonSegmentationRequest.QualityLevel) -> VNGeneratePersonSegmentationRequest {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = bestPixelFormat()
        return request
    }
}
