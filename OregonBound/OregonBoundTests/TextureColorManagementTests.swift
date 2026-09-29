import Foundation
import CoreGraphics
import Testing
@testable import OregonBound

struct TextureColorManagementTests {
    private func rgba(_ bytes: [UInt8]) -> CGImage {
        CGImage(width: bytes.count / 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytes.count, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    @Test func sRGBOutputPreservesOriginalSamples() throws {
        let samples: [UInt8] = [102, 217, 255, 255, 255, 0, 0, 255, 128, 128, 128, 255, 0, 0, 0, 0]
        let result = try #require(TextureLoader.convertedImage(rgba(samples), to: CGColorSpace(name: CGColorSpace.sRGB)!))
        #expect(Array(result.dataProvider!.data! as Data) == samples)
    }

    @Test func p3OutputUsesColorConversionAndPreservesNeutralAndAlpha() throws {
        let source = rgba([102, 217, 255, 255, 255, 0, 0, 255, 128, 128, 128, 255, 0, 0, 0, 0])
        let result = try #require(TextureLoader.convertedImage(source, to: CGColorSpace(name: CGColorSpace.displayP3)!))
        let actual = Array(result.dataProvider!.data! as Data)
        // Standard sRGB→Display P3 conversion; allow one quantization level across ColorSync versions.
        let expected = [132, 214, 251, 255, 234, 51, 35, 255, 128, 128, 128, 255, 0, 0, 0, 0]
        #expect(zip(actual, expected).allSatisfy { abs(Int($0) - $1) <= 1 })
        #expect(actual[8...15] == [128, 128, 128, 255, 0, 0, 0, 0])
    }

    @Test func indexedPaletteAndPixelIndicesAreNeverMutated() throws {
        var palette: [UInt8] = [102, 217, 255, 255, 0, 0]
        let space = try #require(CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 1, colorTable: &palette))
        let indices = Data([0, 1])
        let source = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: 2, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: CGDataProvider(data: indices as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = try #require(TextureLoader.convertedImage(source, to: CGColorSpace(name: CGColorSpace.displayP3)!))
        #expect(source.colorSpace?.colorTable == palette)
        #expect(source.dataProvider!.data! as Data == indices)
        #expect(Array(output.dataProvider!.data! as Data) == [132, 214, 251, 255, 234, 51, 35, 255])
    }
}
