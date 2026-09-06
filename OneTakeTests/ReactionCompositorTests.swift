import CoreImage
@testable import OneTake
import Testing

struct ReactionCompositorTests {
    // MARK: - Geometry

    @Test func aspectFillScaleCoversCanvas() {
        #expect(ReactionCanvasGeometry
            .aspectFillScale(source: CGSize(width: 200, height: 100), canvas: CGSize(width: 100, height: 100)) == 1.0)
        #expect(ReactionCanvasGeometry
            .aspectFillScale(source: CGSize(width: 100, height: 200), canvas: CGSize(width: 100, height: 100)) == 1.0)
        #expect(ReactionCanvasGeometry.aspectFillScale(source: CGSize.zero, canvas: CGSize(width: 100, height: 100)) == 1.0)
    }

    @Test func maskScaleMapsToCamera() {
        let scale = ReactionCanvasGeometry.maskScale(
            maskExtent: CGSize(width: 48, height: 64),
            cameraExtent: CGSize(width: 1920, height: 2560)
        )
        #expect(scale.sx == 40)
        #expect(scale.sy == 40)
    }

    @Test func presenterRectFlipsYToCoreImageSpace() {
        // Unit space is top-left (SwiftUI); CoreImage is bottom-left.
        let rect = ReactionCanvasGeometry.presenterRect(
            unit: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            canvas: CGSize(width: 200, height: 100)
        )
        #expect(rect.origin.x == 0)
        #expect(rect.origin.y == 50)
        #expect(rect.width == 100)
        #expect(rect.height == 50)
    }

    @Test func splitRectsPortraitStacksVertically() {
        let (bg, presenter) = ReactionCanvasGeometry.splitRects(canvas: CGSize(width: 100, height: 200))
        #expect(bg == CGRect(x: 0, y: 100, width: 100, height: 100))
        #expect(presenter == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func splitRectsLandscapeSplitsHorizontally() {
        let (bg, presenter) = ReactionCanvasGeometry.splitRects(canvas: CGSize(width: 200, height: 100))
        #expect(bg == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(presenter == CGRect(x: 100, y: 0, width: 100, height: 100))
    }

    // MARK: - Rendering (CPU context, synthetic frames)

    private func compositor() -> ReactionCompositor {
        ReactionCompositor(cpuOnly: true)
    }

    private func solid(_ color: CIColor, size: CGSize) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// True when the pixel is strongly red. Forces RGBA8 output so the
    /// channel order is deterministic on every device.
    private func isRedDominant(_ image: CIImage, at point: CGPoint, context: CIContext) -> Bool {
        guard let sample = sample(image, at: point, context: context) else { return false }
        return sample.0 > 0.5 && sample.1 < 0.5 && sample.2 < 0.5
    }

    private func sample(_ image: CIImage, at point: CGPoint, context: CIContext) -> (CGFloat, CGFloat, CGFloat)? {
        guard let cg = context.createCGImage(
            image,
            from: image.extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ),
            let provider = cg.dataProvider,
            let data = provider.data as Data?
        else { return nil }
        let bytesPerPixel = cg.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return nil }
        let x = min(max(Int(point.x), 0), cg.width - 1)
        let y = min(max(Int(point.y), 0), cg.height - 1)
        let offset = y * cg.bytesPerRow + x * bytesPerPixel
        guard offset + 2 < data.count else { return nil }
        return (CGFloat(data[offset]) / 255, CGFloat(data[offset + 1]) / 255, CGFloat(data[offset + 2]) / 255)
    }

    @Test func silhouetteWithFullMaskShowsCamera() {
        let comp = compositor()
        let size = CGSize(width: 160, height: 160)
        let out = comp.composite(
            camera: solid(.red, size: size),
            mask: solid(.white, size: size),
            background: solid(.blue, size: size),
            canvasSize: size,
            style: ReactionStyle(layout: .silhouette, outline: .off)
        )
        #expect(out.extent.size == size)
        #expect(isRedDominant(out, at: CGPoint(x: 80, y: 80), context: comp.context))
    }

    @Test func silhouetteWithNilMaskFallsBackToCamera() {
        let comp = compositor()
        let size = CGSize(width: 160, height: 160)
        let out = comp.composite(
            camera: solid(.red, size: size),
            mask: nil,
            background: solid(.blue, size: size),
            canvasSize: size,
            style: ReactionStyle(layout: .silhouette, outline: .off)
        )
        #expect(isRedDominant(out, at: CGPoint(x: 80, y: 80), context: comp.context))
    }

    @Test func circleKeepsBackgroundOutsideBubble() {
        let comp = compositor()
        let size = CGSize(width: 200, height: 200)
        var style = ReactionStyle(layout: .circle, outline: .off)
        style.presenterUnitRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let out = comp.composite(
            camera: solid(.red, size: size),
            mask: solid(.white, size: size),
            background: solid(.blue, size: size),
            canvasSize: size,
            style: style
        )
        // Center of the bubble is camera…
        #expect(isRedDominant(out, at: CGPoint(x: 100, y: 100), context: comp.context))
        // …corner far outside the bubble stays background (not red-dominant).
        #expect(!isRedDominant(out, at: CGPoint(x: 5, y: 5), context: comp.context))
    }

    @Test func splitKeepsBackgroundOnItsHalf() {
        let comp = compositor()
        let size = CGSize(width: 100, height: 200)
        let out = comp.composite(
            camera: solid(.red, size: size),
            mask: nil,
            background: solid(.blue, size: size),
            canvasSize: size,
            style: ReactionStyle(layout: .split, outline: .off, maskEnabled: false)
        )
        // CGImage row 0 is the top = background half in portrait.
        #expect(!isRedDominant(out, at: CGPoint(x: 50, y: 20), context: comp.context))
        #expect(isRedDominant(out, at: CGPoint(x: 50, y: 180), context: comp.context))
    }

    @Test func outlineDoesNotCrashAndPreservesCenter() {
        let comp = compositor()
        let size = CGSize(width: 160, height: 160)
        for outline in ReactionOutline.allCases {
            let out = comp.composite(
                camera: solid(.red, size: size),
                mask: solid(.white, size: size),
                background: solid(.blue, size: size),
                canvasSize: size,
                style: ReactionStyle(layout: .silhouette, outline: outline)
            )
            #expect(out.extent.size == size)
        }
    }
}
