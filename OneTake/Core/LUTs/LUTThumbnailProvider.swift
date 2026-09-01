//
//  LUTThumbnailProvider.swift
//  OneTake
//

//  See: docs/ARCHITECTURE.md §6 + openspec/specs/trim-color-export/spec.md
import CoreImage
import Metal
import SwiftUI
import UIKit

/// Renders cached 40×24 swatches for each `LUTPreset` by applying its
/// `.cube` transform to a neutral gradient. Natural returns a neutral gray
/// without a filter pass; missing cube data falls back to a tinted placeholder.
enum LUTCubeThumbnailProvider {
    private static let cache = NSCache<NSString, CGImage>()
    private static let thumbnailSize = CGSize(width: 40, height: 24)

    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    private static var lastMtimes: [String: Date] = [:]

    /// Cached swatch for `preset`. Creates on first access; subsequent calls
    /// hit `NSCache`. Call off the main thread for the initial render.
    /// Invalidates when the underlying `.cube` file's mtime changes.
    static func thumbnail(for preset: LUTPreset) -> CGImage? {
        let key = preset.rawValue as NSString
        if let url = preset.resourceURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date
        // swiftlint:disable:next opening_brace
        {
            if let last = lastMtimes[preset.rawValue], last != mtime {
                cache.removeObject(forKey: key)
            }
            lastMtimes[preset.rawValue] = mtime
        }
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image: CGImage? = if preset == .natural {
            renderNeutral()
        } else if let data = LUTCubeLoader.data(for: preset),
                  let filtered = filteredGradient(using: data)
        // swiftlint:disable:next opening_brace
        {
            filtered
        } else {
            renderPlaceholder(for: preset)
        }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    /// Invalidate a single preset (e.g., when its `.cube` file mtime changes).
    static func invalidate(_ preset: LUTPreset) {
        cache.removeObject(forKey: preset.rawValue as NSString)
    }

    /// Invalidate all cached swatches.
    static func invalidateAll() {
        cache.removeAllObjects()
    }

    // MARK: - Private rendering

    private static func baseGradient() -> CIImage {
        let rect = CGRect(origin: .zero, size: thumbnailSize)
        // Blue → Red horizontal gradient gives a colorful ramp that makes
        // warm/cool LUT shifts obvious; monochrome collapses it to gray.
        let filter = CIFilter(name: "CILinearGradient")
        filter?.setValue(CIVector(x: 0, y: rect.midY), forKey: "inputPoint0")
        filter?.setValue(CIVector(x: rect.maxX, y: rect.midY), forKey: "inputPoint1")
        filter?.setValue(CIColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1), forKey: "inputColor0")
        filter?.setValue(CIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1), forKey: "inputColor1")
        return (filter?.outputImage?.cropped(to: rect)) ?? CIImage(color: CIColor.gray).cropped(to: rect)
    }

    private static func filteredGradient(using cubeData: Data) -> CGImage? {
        let base = baseGradient()
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(base, forKey: kCIInputImageKey)
        filter.setValue(Float(LUTCubeLoader.cubeDimension), forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        guard let output = filter.outputImage?.cropped(to: base.extent) else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    private static func renderNeutral() -> CGImage? {
        let rect = CGRect(origin: .zero, size: thumbnailSize)
        let base = CIImage(color: CIColor(red: 0.6, green: 0.6, blue: 0.6)).cropped(to: rect)
        return ciContext.createCGImage(base, from: rect)
    }

    private static func renderPlaceholder(for preset: LUTPreset) -> CGImage? {
        // Tinted placeholder so the row still conveys a hue per preset.
        let rect = CGRect(origin: .zero, size: thumbnailSize)
        let color = switch preset {
        case .warmStudio: CIColor(red: 0.85, green: 0.65, blue: 0.35)
        case .cinematicContrast: CIColor(red: 0.35, green: 0.35, blue: 0.45)
        case .cleanMonochrome: CIColor(red: 0.5, green: 0.5, blue: 0.5)
        default: CIColor(red: 0.6, green: 0.6, blue: 0.6)
        }
        let base = CIImage(color: color).cropped(to: rect)
        return ciContext.createCGImage(base, from: rect)
    }
}

/// Reusable 40×24 swatch view with cached async loading.
struct LUTSwatchView: View {
    let preset: LUTPreset
    @State private var cgImage: CGImage?

    var body: some View {
        Group {
            if let cgImage {
                Image(decorative: cgImage, scale: 2, orientation: .up)
                    .resizable()
                    .frame(width: 40, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 40, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            }
        }
        .task(id: preset.rawValue) {
            let image = await Task.detached(priority: .userInitiated) {
                LUTCubeThumbnailProvider.thumbnail(for: preset)
            }.value
            await MainActor.run { cgImage = image }
        }
    }
}
