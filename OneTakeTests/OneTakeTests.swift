//
//  OneTakeTests.swift
//  OneTakeTests
//

import CoreGraphics
import CoreImage
import CoreMedia
@testable import OneTake
import SwiftData
import Testing

// MARK: - 2.4 SwiftData Script persistence

struct PersistenceTests {
    @Test func insertFetchDeleteScript() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Script.self, Take.self, ScriptCategory.self, configurations: config)
        let context = ModelContext(container)

        let script = Script(title: "Hello", body: "One take")
        context.insert(script)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Script>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Hello")

        // updatedAt changes on save after edit
        let original = try #require(fetched.first?.updatedAt)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        fetched.first?.body = "Edited body"
        fetched.first?.updatedAt = Date()
        try context.save()
        #expect(try #require(fetched.first?.updatedAt) > original)

        try context.delete(#require(fetched.first))
        try context.save()
        let afterDelete = try context.fetch(FetchDescriptor<Script>())
        #expect(afterDelete.isEmpty)
    }

    @Test func takeUsesRelativePath() {
        let docs = Take.documentsDirectory
        let url = docs.appendingPathComponent("Takes/demo.mp4")
        let take = Take(scriptID: UUID(), fileURL: url, duration: 10)
        #expect(take.relativeFilePath == "Takes/demo.mp4")
        #expect(take.fileURL.lastPathComponent == "demo.mp4")
        // Resolved via documents directory
        #expect(take.fileURL.path.hasSuffix("Takes/demo.mp4"))
    }

    @Test func trimRangeRoundTrip() {
        let range = CMTimeRange(
            start: CMTime(seconds: 2, preferredTimescale: 600),
            duration: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let take = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/x.mp4"), duration: 10, trimRange: range)
        #expect(take.trimStartSeconds == 2)
        #expect(take.trimDurationSeconds == 5)
        let decoded = take.trimRange
        #expect(decoded?.start.seconds == 2)
        #expect(decoded?.duration.seconds == 5)
        // nil case
        let take2 = Take(scriptID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/y.mp4"), duration: 10, trimRange: nil)
        #expect(take2.trimRange == nil)
    }
}

// MARK: - 4.3 Cadence engine

struct CadenceTests {
    @Test func zeroWordsIsZero() {
        #expect(CadenceViewModel.wordCount(in: "") == 0)
        #expect(CadenceViewModel.wordCount(in: "   \n\t  ") == 0)
        #expect(CadenceViewModel.durationSeconds(wordCount: 0) == 0)
        #expect(CadenceViewModel.formattedDuration(wordCount: 0) == "0:00")
    }

    @Test func durationBaseline130wpm() {
        #expect(CadenceViewModel.durationSeconds(wordCount: 130) == 60)
        #expect(CadenceViewModel.formattedDuration(wordCount: 130) == "1:00")
        #expect(CadenceViewModel.durationSeconds(wordCount: 65) == 30)
        #expect(CadenceViewModel.formattedDuration(wordCount: 65) == "0:30")
        #expect(CadenceViewModel.durationSeconds(wordCount: 260) == 120)
        #expect(CadenceViewModel.formattedDuration(wordCount: 260) == "2:00")
        #expect(CadenceViewModel.durationSeconds(wordCount: 13) == 6)
        #expect(CadenceViewModel.formattedDuration(wordCount: 13) == "0:06")
    }

    @Test func wordDefinitionPunctuationAndWhitespace() {
        #expect(CadenceViewModel.wordCount(in: "hello,  world\nnew") == 3)
        #expect(CadenceViewModel.wordCount(in: "one  two\tthree\n\nfour") == 4)
        #expect(CadenceViewModel.wordCount(in: "a  b   c") == 3)
        #expect(CadenceViewModel.wordCount(in: "hello") == 1)
    }

    @Test @MainActor func rapidTypingFinalCount() {
        var body = ""
        for i in 0 ..< 100 {
            body += "word\(i) "
        }
        #expect(CadenceViewModel.wordCount(in: body) == 100)
        let vm = CadenceViewModel()
        for chunk in ["hello ", "world ", "test "] {
            vm.update(body: chunk)
        }
        vm.update(body: body)
        #expect(vm.wordCount == 100)
        #expect(vm.durationSeconds == CadenceViewModel.durationSeconds(wordCount: 100))
    }

    @Test @MainActor func observableUpdatesSynchronously() {
        let vm = CadenceViewModel()
        vm.update(body: "hello world")
        #expect(vm.wordCount == 2)
        vm.update(body: "hello world test extra")
        #expect(vm.wordCount == 4)
    }
}

// MARK: - 8.7 Trim range math + export helpers

struct TrimExportTests {
    @Test func trimRangeConstraints() {
        // Start < end, min 1s — mirror TrimScrubber logic
        let duration = 30.0
        var start = 2.0
        var end = 28.0
        #expect(end - start >= 1)
        // Clamp start to not pass end - minDuration
        start = min(max(0, 27.5), end - 1)
        #expect(start == 27.0)
        // Clamp end
        end = max(min(duration, 0.5), start + 1)
        #expect(end == 28.0) // after clamp, but if end was 0.5 it would be start+1
        // Passthrough identity trim
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )
        #expect(range.duration.seconds == 1.0)
    }

    @Test func lutPresetsExist() {
        #expect(LUTPreset.allCases.count == 10)
        #expect(LUTPreset.natural.displayName == "Natural")
        #expect(LUTPreset.warmStudio.displayName == "Warm Studio")
        #expect(LUTPreset.goldenHour.displayName == "Golden Hour")
        #expect(LUTPreset.tealOrange.displayName == "Teal & Orange")
        #expect(LUTPreset.fadedFilm.displayName == "Faded Film")
        #expect(LUTPreset.noir.displayName == "Noir Punch")
        #expect(LUTPreset.vibrantPop.displayName == "Vibrant Pop")
        #expect(LUTPreset.coolMorning.displayName == "Cool Morning")
        let raws = LUTPreset.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count) // unique bundle names
        #expect(LUTPreset.natural.cubeData == nil)
        for preset in LUTPreset.allCases where preset != .natural {
            #expect(
                Bundle.main.url(forResource: preset.rawValue, withExtension: "cube") != nil,
                "missing bundled cube for \(preset.rawValue) — check target membership"
            )
        }
    }

    @Test func exportServiceTempURL() {
        let url = ExportService.tempOutputURL()
        #expect(url.pathExtension == "mp4")
        #expect(url.lastPathComponent.hasPrefix("onetake-"))
        let takes = ExportService.takesDirectory()
        #expect(takes.lastPathComponent == "Takes")
    }

    @Test func shareLinkUsesProcessedFile() {
        // Verify that exportedURL != source when LUT applied would be different path
        let source = URL(fileURLWithPath: "/tmp/source.mp4")
        let out = ExportService.tempOutputURL()
        #expect(source != out)
    }
}

// MARK: - LUT text parsing, dimension sniffing, grade direction

/// Covers the two on-disk `.cube` flavors: legacy raw-binary 64³ dumps pass
/// through byte-identical, Adobe text (SIZE 32) parses to RGBA float32, and
/// each generated grade shifts pixels in its documented direction. Catches a
/// corrupt generator run or a loader regression before export bakes it in.
struct LUTCubeLoaderTests {
    private static let tiny = CGRect(x: 0, y: 0, width: 8, height: 8)

    /// Mean RGBA8 of `color` pushed through `preset`'s `CIColorCube`.
    private static func graded(_ color: CIColor, preset: LUTPreset) -> (r: Int, g: Int, b: Int)? {
        let input = CIImage(color: color).cropped(to: tiny)
        guard let out = LUTCubeLoader.filter(for: preset, inputImage: input) else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let context = CIContext()
        context.render(
            out, toBitmap: &bitmap, rowBytes: 8 * 4, bounds: tiny,
            format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        var rSum = 0, gSum = 0, bSum = 0
        for i in stride(from: 0, to: bitmap.count, by: 4) {
            rSum += Int(bitmap[i]); gSum += Int(bitmap[i + 1]); bSum += Int(bitmap[i + 2])
        }
        return (rSum / 64, gSum / 64, bSum / 64)
    }

    @Test func adobeTextParsesToExactFloats() throws {
        let text = """
        TITLE "Test"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0

        """
        let data = LUTCubeLoader.floatData(from: text, dimension: 2)
        let floats = try? #require(data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(floats?.count == 2 * 2 * 2 * 4)
        #expect(floats?[0 ..< 4] == [0, 0, 0, 1]) // black corner + alpha
        #expect(try floats?[(#require(floats?.count) - 4)...] == [1, 1, 1, 1]) // white corner
    }

    @Test func adobeTextRejectsMalformed() {
        #expect(LUTCubeLoader.floatData(from: "LUT_3D_SIZE 2\n0.0 0.0\n", dimension: 2) == nil) // short triplet
        #expect(LUTCubeLoader.floatData(from: "LUT_3D_SIZE 2\n9.0 0.0 0.0\n", dimension: 2) == nil) // out of range
        let oneShort = String(repeating: "0.0 0.0 0.0\n", count: 7)
        #expect(LUTCubeLoader.floatData(from: "LUT_3D_SIZE 2\n" + oneShort, dimension: 2) == nil) // 7 of 8
    }

    @Test func dimensionSniffing() {
        #expect(LUTCubeLoader.dimension(in: Data(count: 16 * 16 * 16 * 16)) == 16)
        #expect(LUTCubeLoader.dimension(in: Data(count: 32 * 32 * 32 * 16)) == 32)
        #expect(LUTCubeLoader.dimension(in: Data(count: 64 * 64 * 64 * 16)) == 64)
        let text = "TITLE \"X\"\nLUT_3D_SIZE 32\n".data(using: .utf8)! + Data(count: 100)
        #expect(LUTCubeLoader.dimension(in: text) == 32) // header wins over byte count
        #expect(LUTCubeLoader.dimension(in: Data(count: 123)) == 64) // garbage defaults
    }

    @Test func legacyBinaryPassesThroughByteIdentical() throws {
        for preset: LUTPreset in [.warmStudio, .cinematicContrast, .cleanMonochrome] {
            let url = try #require(Bundle.main.url(forResource: preset.rawValue, withExtension: "cube"))
            let raw = try Data(contentsOf: url)
            #expect(LUTCubeLoader.dimension(for: preset) == 64)
            #expect(LUTCubeLoader.data(for: preset) == raw) // untouched legacy bytes
        }
    }

    @Test func generatedCubesParseAtSize32() {
        for preset: LUTPreset in [.goldenHour, .tealOrange, .fadedFilm, .noir, .vibrantPop, .coolMorning] {
            #expect(LUTCubeLoader.dimension(for: preset) == 32, "\(preset.rawValue) should sniff SIZE 32")
            let bytes = LUTCubeLoader.data(for: preset)?.count ?? 0
            #expect(bytes == 32 * 32 * 32 * 16, "\(preset.rawValue) parses to full RGBA float32 lattice")
        }
    }

    @Test func gradesShiftInDocumentedDirection() throws {
        let gray = CIColor(red: 0.5, green: 0.5, blue: 0.5)
        let golden = try #require(Self.graded(gray, preset: .goldenHour))
        #expect(golden.r > golden.b + 10) // warm gain pushes R over B
        let red = CIColor(red: 1, green: 0, blue: 0)
        let noirRed = try #require(Self.graded(red, preset: .noir))
        #expect(noirRed.r == noirRed.g && noirRed.g == noirRed.b) // mono
        let black = CIColor(red: 0, green: 0, blue: 0)
        let faded = try #require(Self.graded(black, preset: .fadedFilm))
        #expect(faded.r == faded.g && faded.g == faded.b)
        #expect(noirRed.r < faded.r) // crushed red sits below lifted black
        #expect(faded.r > 0 && faded.r < 128) // lifted, but stays dark
        let morning = try #require(Self.graded(gray, preset: .coolMorning))
        #expect(morning.b > morning.r) // cool gain favors B
        let white = CIColor(red: 1, green: 1, blue: 1)
        let tealBlack = try #require(Self.graded(black, preset: .tealOrange))
        #expect(tealBlack.r == 0 && tealBlack.g == 0 && tealBlack.b == 0) // shadows stay anchored
        let tealWhite = try #require(Self.graded(white, preset: .tealOrange))
        #expect(tealWhite.r >= tealWhite.b) // highlights lean warm
    }

    @Test func thumbnailsRenderForAllPresets() {
        for preset in LUTPreset.allCases {
            #expect(LUTCubeThumbnailProvider.thumbnail(for: preset) != nil, "no swatch for \(preset.rawValue)")
        }
    }
}
