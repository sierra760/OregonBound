import Foundation
import CoreGraphics
import Testing
import SpriteKit
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
    #if os(macOS)
    @MainActor @Test func nativeUploadPreservesEveryTransparentCorner() throws {
        var pixels = Array(repeating: [UInt8(0),0,0,255],count: 25)
        for index in [0,4,20,24] { pixels[index] = [0,0,0,0] }
        pixels[1] = [255,255,255,255]
        let source = try #require(CGImage(width: 5,height: 5,bitsPerComponent: 8,bitsPerPixel: 32,
            bytesPerRow: 20,space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels.flatMap { $0 }) as CFData)!,decode: nil,
            shouldInterpolate: false,intent: .defaultIntent))
        let view = SKView(frame: NSRect(x: 0,y: 0,width: 32,height: 32))
        let window = NSWindow(contentRect: view.frame,styleMask: [.borderless],backing: .buffered,defer: false)
        window.contentView = view
        let scene = SKScene(size: view.frame.size); scene.backgroundColor = .white
        let sprite = SKSpriteNode(texture: TextureLoader.texture(cgImage: source,renderingIn: view))
        sprite.position = CGPoint(x: 10.5,y: 21.5)
        scene.addChild(sprite); view.presentScene(scene); view.isPaused = true
        let rendered = try #require(view.texture(from: scene,crop: CGRect(x: 0,y: 0,width: 32,height: 32))).cgImage()
        let context = try #require(CGContext(data: nil,width: 32,height: 32,bitsPerComponent: 8,
            bytesPerRow: 128,space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .none
        context.draw(rendered,in: CGRect(x: 0,y: 0,width: 32,height: 32))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 8...12 { for x in 8...12 {
            let corner = (x == 8 || x == 12) && (y == 8 || y == 12)
            #expect(bytes[(y*32+x)*4] == (corner || (x == 9 && y == 8) ? 255 : 0))
        } }
        withExtendedLifetime(window) {}
    }
    #endif

}
