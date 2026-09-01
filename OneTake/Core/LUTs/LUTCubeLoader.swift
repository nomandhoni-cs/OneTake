//
//  LUTCubeLoader.swift
//  OneTake
//

import CoreImage
import Foundation

enum LUTCubeLoader {
    static let cubeDimension = 64
    private static var cache: [String: Data] = [:]

    static func data(for preset: LUTPreset) -> Data? {
        if preset == .natural {
            return nil
        }
        if let cached = cache[preset.rawValue] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: preset.rawValue, withExtension: "cube"),
              let data = try? Data(contentsOf: url)
        else {
            debugPrint("[LUT] missing cube for \(preset.rawValue)")
            return nil
        }
        cache[preset.rawValue] = data
        return data
    }

    static func filter(for preset: LUTPreset, inputImage: CIImage) -> CIImage? {
        guard preset != .natural else { return inputImage }
        guard let data = data(for: preset) else { return inputImage }
        guard let filter = CIFilter(name: "CIColorCube") else { return inputImage }
        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(Float(cubeDimension), forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        return filter.outputImage ?? inputImage
    }
}
