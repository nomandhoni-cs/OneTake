//
//  ReactionCompositor.swift
//  OneTake
//
//  Owns: GPU compositing of camera frame + Vision person mask + background
//  into one reaction frame (silhouette / circle-PiP / split + outline glow).
//  Why: CoreImage on a shared Metal `CIContext` keeps preview and recorded
//  file on one code path (WYSIWYG); pure geometry helpers stay testable.
//  See: docs/ARCHITECTURE.md §6 + openspec/changes/reaction-studio-cutout/specs/reaction-studio/spec.md
//
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Metal
import SwiftUI
import UIKit

/// Unit-space presenter rect + style knobs for one composite.
struct ReactionStyle {
    var layout: ReactionLayout = .circle
    /// Unit rect (0...1) in canvas space for the presenter (circle/split).
    var presenterUnitRect: CGRect = .init(
        x: ReactionPresenterDefaults.centerX - ReactionPresenterDefaults.width / 2,
        y: ReactionPresenterDefaults.centerY - ReactionPresenterDefaults.height / 2,
        width: ReactionPresenterDefaults.width,
        height: ReactionPresenterDefaults.height
    )
    var outline: ReactionOutline = .white
    /// `false` on weak silicon (A14 fallback) — rectangular presenter, no mask.
    var maskEnabled = true
}

/// Pure canvas geometry — no GPU, fully unit-testable.
enum ReactionCanvasGeometry {
    /// Aspect-fill scale mapping `source` onto `canvas`.
    static func aspectFillScale(source: CGSize, canvas: CGSize) -> CGFloat {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0 else { return 1 }
        return max(canvas.width / source.width, canvas.height / source.height)
    }

    /// Vision mask → camera frame scale (mask is lower resolution).
    static func maskScale(maskExtent: CGSize, cameraExtent: CGSize) -> (sx: CGFloat, sy: CGFloat) {
        guard maskExtent.width > 0, maskExtent.height > 0 else { return (1, 1) }
        return (cameraExtent.width / maskExtent.width, cameraExtent.height / maskExtent.height)
    }

    /// Unit rect → pixel rect in canvas space (CoreImage origin is bottom-left;
    /// unit space here is top-left like SwiftUI, so Y is flipped).
    static func presenterRect(unit: CGRect, canvas: CGSize) -> CGRect {
        let clamped = CGRect(
            x: min(max(unit.origin.x, 0), 1),
            y: min(max(unit.origin.y, 0), 1),
            width: min(max(unit.width, ReactionPresenterDefaults.minSide), 1),
            height: min(max(unit.height, ReactionPresenterDefaults.minSide), 1)
        )
        return CGRect(
            x: clamped.origin.x * canvas.width,
            y: (1 - clamped.origin.y - clamped.height) * canvas.height,
            width: clamped.width * canvas.width,
            height: clamped.height * canvas.height
        )
    }

    /// Split-screen halves: portrait → top/bottom, landscape → left/right.
    /// Returns `(background, presenter)`.
    static func splitRects(canvas: CGSize) -> (CGRect, CGRect) {
        if canvas.height >= canvas.width {
            let half = canvas.height / 2
            return (
                CGRect(x: 0, y: half, width: canvas.width, height: half),
                CGRect(x: 0, y: 0, width: canvas.width, height: half)
            )
        }
        let half = canvas.width / 2
        return (
            CGRect(x: 0, y: 0, width: half, height: canvas.height),
            CGRect(x: half, y: 0, width: half, height: canvas.height)
        )
    }
}

/// Composites reaction frames on the GPU. Not thread-safe — call from one
/// serial pipeline queue.
final class ReactionCompositor {
    let context: CIContext

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = (try? CIContext(mtlDevice: device, options: [.cacheIntermediates: false]))
                ?? CIContext(options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    /// Test seam — CPU context so unit tests never need Metal.
    init(cpuOnly: Bool) {
        _ = cpuOnly
        context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    }

    // MARK: - Composite

    /// Blends camera over background per `style` at `canvasSize` (e.g. 1080×1920).
    /// The result is always cropped to the canvas so the writer pool render
    /// and preview share exact dimensions (glow dilation can expand extents).
    func composite(camera: CIImage, mask: CIImage?, background: CIImage, canvasSize: CGSize, style: ReactionStyle) -> CIImage {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let bg = aspectFilled(background, canvas: canvas)
        let cam = aspectFilled(camera, canvas: canvas)
        let alignedMask = mask.map { alignMask($0, to: cam.extent.size) }

        let framed: CIImage
        switch style.layout {
        case .silhouette:
            framed = compositeSilhouette(camera: cam, mask: alignedMask, over: bg, style: style)
        case .circle:
            let rect = ReactionCanvasGeometry.presenterRect(unit: style.presenterUnitRect, canvas: canvasSize)
            framed = compositeCircle(camera: cam, mask: alignedMask, over: bg, rect: rect, style: style)
        case .split:
            let (bgRect, presenterRect) = ReactionCanvasGeometry.splitRects(canvas: canvasSize)
            framed = compositeSplit(camera: cam, mask: alignedMask, over: bg, halves: (bgRect, presenterRect), style: style)
        }
        return framed.cropped(to: canvas)
    }

    // MARK: - Layouts

    private func compositeSilhouette(camera: CIImage, mask: CIImage?, over bg: CIImage, style: ReactionStyle) -> CIImage {
        guard style.maskEnabled, let mask else { return camera.composited(over: bg) }
        let glow = outlineGlow(mask: mask, bounds: camera.extent, outline: style.outline)
        let cutout = blend(foreground: camera, mask: mask)
        return cutout.composited(over: glow.composited(over: bg))
    }

    private func compositeCircle(camera: CIImage, mask: CIImage?, over bg: CIImage, rect: CGRect, style: ReactionStyle) -> CIImage {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let circle = circleMask(center: center, radius: radius, bounds: bg.extent)
        let framed = aspectFilled(camera, canvas: rect)
        let framedMask: CIImage?
        if style.maskEnabled, let mask {
            let scaled = scaleToRect(alignMask(mask, to: camera.extent.size), rect: rect, source: camera.extent)
            framedMask = multiply(scaled, circle)
        } else {
            framedMask = circle
        }
        let glow: CIImage = if style.maskEnabled, let framedMask {
            outlineGlow(mask: framedMask, bounds: bg.extent, outline: style.outline)
        } else {
            outlineGlow(mask: circle, bounds: bg.extent, outline: style.outline)
        }
        let cutout = blend(foreground: framed, mask: framedMask)
        return cutout.composited(over: glow.composited(over: bg))
    }

    private func compositeSplit(
        camera: CIImage,
        mask: CIImage?,
        over bg: CIImage,
        halves: (background: CGRect, presenter: CGRect),
        style: ReactionStyle
    ) -> CIImage {
        let bgHalf = bg.cropped(to: halves.background)
        let framed = aspectFilled(camera, canvas: halves.presenter)
        let framedMask: CIImage? = if style.maskEnabled, let mask {
            scaleToRect(alignMask(mask, to: camera.extent.size), rect: halves.presenter, source: camera.extent)
        } else {
            nil
        }
        let cutout: CIImage
        if let framedMask {
            let glow = outlineGlow(mask: framedMask, bounds: halves.presenter, outline: style.outline)
            cutout = blend(foreground: framed, mask: framedMask).composited(over: glow)
        } else {
            cutout = framed
        }
        // Presenter half over full BG, then BG half pinned on top of its side.
        return bgHalf.composited(over: cutout.composited(over: bg))
    }

    // MARK: - Primitives

    private func blend(foreground: CIImage, mask: CIImage?) -> CIImage {
        guard let mask else { return foreground }
        let filter = CIFilter.blendWithMask()
        filter.inputImage = foreground
        filter.maskImage = mask
        filter.backgroundImage = .empty()
        return filter.outputImage ?? foreground
    }

    private func multiply(_ lhs: CIImage, _ rhs: CIImage) -> CIImage {
        let filter = CIFilter.multiplyCompositing()
        filter.inputImage = lhs
        filter.backgroundImage = rhs
        return filter.outputImage ?? lhs
    }

    /// Tinted ring around `mask` (dilated minus original), or transparent.
    /// Uses the string filter API for SDK-stable keys.
    private func outlineGlow(mask: CIImage, bounds: CGRect, outline: ReactionOutline) -> CIImage {
        guard let tint = outline.color else { return .empty() }
        guard let dilate = CIFilter(name: "CIMorphologyMaximum") else { return .empty() }
        dilate.setValue(mask, forKey: kCIInputImageKey)
        dilate.setValue(5.0, forKey: kCIInputRadiusKey)
        guard let grown = dilate.outputImage else { return .empty() }
        let subtract = CIFilter.subtractBlendMode()
        subtract.inputImage = grown
        subtract.backgroundImage = mask
        guard let ring = subtract.outputImage else { return .empty() }
        guard let color = CIFilter(name: "CIConstantColorGenerator") else { return .empty() }
        color.setValue(CIColor(color: UIColor(tint)), forKey: kCIInputColorKey)
        let tinted = CIFilter.blendWithMask()
        tinted.inputImage = color.outputImage
        tinted.maskImage = ring
        tinted.backgroundImage = .empty()
        return tinted.outputImage ?? .empty()
    }

    private func circleMask(center: CGPoint, radius: CGFloat, bounds: CGRect) -> CIImage {
        guard let gradient = CIFilter(name: "CIRadialGradient") else { return .empty() }
        gradient.setValue(CIVector(x: center.x, y: center.y), forKey: "inputCenter")
        gradient.setValue(Float(radius), forKey: "inputRadius0")
        gradient.setValue(Float(radius + 1), forKey: "inputRadius1")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(CIColor.clear, forKey: "inputColor1")
        return (gradient.outputImage ?? .empty()).cropped(to: bounds)
    }

    private func alignMask(_ mask: CIImage, to cameraSize: CGSize) -> CIImage {
        let extent = mask.extent
        let (sx, sy) = ReactionCanvasGeometry.maskScale(maskExtent: extent.size, cameraExtent: cameraSize)
        return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }

    private func aspectFilled(_ image: CIImage, canvas: CGRect) -> CIImage {
        let scale = ReactionCanvasGeometry.aspectFillScale(source: image.extent.size, canvas: canvas.size)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaled.extent
        let origin = CGPoint(
            x: canvas.origin.x + (canvas.width - extent.width) / 2 - extent.origin.x,
            y: canvas.origin.y + (canvas.height - extent.height) / 2 - extent.origin.y
        )
        return scaled.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y)).cropped(to: canvas)
    }

    private func scaleToRect(_ image: CIImage, rect: CGRect, source: CGRect) -> CIImage {
        let sx = rect.width / max(source.width, 1)
        let sy = rect.height / max(source.height, 1)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let extent = scaled.extent
        return scaled.transformed(by: CGAffineTransform(
            translationX: rect.origin.x - extent.origin.x,
            y: rect.origin.y - extent.origin.y
        )).cropped(to: rect)
    }

    // MARK: - Render

    func renderToPixelBuffer(_ image: CIImage, to buffer: CVPixelBuffer) {
        context.render(image, to: buffer)
    }

    func makeCGImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}
