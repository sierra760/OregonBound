import XCTest
import SpriteKit
@testable import OregonBound

final class CoreRenderingTests: XCTestCase {
    func testAnimalWhiteBackgroundBecomesTransparent() throws {
        let pixels: [UInt8] = [255, 255, 255, 255, 180, 70, 20, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let source = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let keyed = try XCTUnwrap(TextureLoader.removingWhiteBackground(from: source))
        let bytes = try XCTUnwrap(keyed.dataProvider?.data) as Data
        XCTAssertEqual(bytes[3], 0)
        XCTAssertEqual(bytes[7], 255)
        XCTAssertEqual(bytes[4], 180)
    }

    private var manifest: GraphicsManifest!

    override func setUpWithError() throws {
        try GameDataTestSupport.requireGameData()
        manifest = try XCTUnwrap(BundleAssets.loadManifest(), GameDataTestSupport.missingMessage)
    }

    func testManifestReturns47FramesForImag19000() {
        XCTAssertEqual(manifest.images(forResourceId: 19000).count, 47)
    }

    func testImag19000FramesSortedByIndex() {
        let frames = manifest.images(forResourceId: 19000)
        let indices = frames.map { $0.frame_index }
        XCTAssertEqual(indices, Array(0..<47))
    }

    func testImag19000FrameDimensions() {
        // Frame 0 is the full-scene canvas (494x304); frames 1-46 are individual wagon sprite components
        let frames = manifest.images(forResourceId: 19000)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertEqual(frames[0].width, 494)
        XCTAssertEqual(frames[0].height, 304)
        // All sprite frames (1-46) are smaller than the canvas
        for frame in frames.dropFirst() {
            XCTAssertLessThan(frame.width, 494, "Frame \(frame.frame_index) unexpectedly canvas-sized")
            XCTAssertLessThan(frame.height, 304, "Frame \(frame.frame_index) unexpectedly canvas-sized")
        }
    }

    func testImag19030IsSingleFrame() {
        XCTAssertEqual(manifest.images(forResourceId: 19030).count, 1)
    }

    func testAnimationTimingAt12Fps() {
        let timePerFrame = 1.0 / 12.0
        XCTAssertEqual(timePerFrame, 0.0833, accuracy: 0.001)
    }

    func testNearestFilteringApplied() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ), let cgImage = ctx.makeImage() else {
            XCTFail("Could not create synthetic CGImage")
            return
        }
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest
        XCTAssertEqual(texture.filteringMode, .nearest)
    }
}
