import CoreGraphics
import Foundation
import Testing
@testable import OregonBound

struct OriginalTravelAnimationTests {
    private func input(pace: Int = 0, destination: Int = 0, remaining: Int = 102,
                       month: Int = 4, weather: Int = 0, snow: Int = 0) -> OriginalTravelAnimation.Input {
        .init(pace: pace, destinationIndex: destination, remainingMiles: remaining,
              month: month, weather: weather, snow: snow)
    }

    @Test func alternateStripUsesItsOwnWidthAtCreationAndWrap() {
        var animation = OriginalTravelAnimation(input: input(pace: 2, remaining: 1000), upperStripWidth: 581, lowerStripWidth: 700)
        #expect(animation.upperStripX == -255 && animation.lowerStripX == -374)
        #expect(animation.drawCommands[1].destination.width == 581)
        #expect(animation.drawCommands[1].clipped?.source.x == 319)
        // Keep the landmark in transit while exercising a complete strip cycle.
        for tick in 0..<319 {
            animation.apply(input(pace: 2, remaining: 1000+tick))
            animation.step()
        }
        #expect(animation.upperStripX == 64)
        animation.step()
        #expect(animation.upperStripX == -254)
        #expect(animation.drawCommands[2].destination.width == 700)
    }
    @Test func originalCompositionAndStripCrop() {
        let animation = OriginalTravelAnimation(input: input())
        let commands = animation.drawCommands
        #expect(commands.map(\.frame) == [0,1,2,20,3])
        #expect(commands[0].destination == .init(x: 64, y: 9, width: 262, height: 77))
        #expect(commands[1].clipped?.source == .init(x: 524, y: 0, width: 262, height: 14))
        #expect(commands[2].clipped?.source == .init(x: 524, y: 0, width: 262, height: 5))
        #expect(commands[3].clipped == nil)
        #expect(commands[4].destination == .init(x: 256, y: 54, width: 67, height: 25))
    }

    @Test(arguments: [0,1,2]) func paceControlsOriginalPeriods(_ pace: Int) {
        var animation = OriginalTravelAnimation(input: input(pace: pace))
        for _ in 0..<(3 - pace - 1) { animation.step() }
        #expect(animation.wagonFrame == 3)
        #expect(animation.upperStripX == -460)
        animation.step()
        #expect(animation.wagonFrame == 4)
        #expect(animation.upperStripX == -459)
        #expect(animation.lowerStripX == -460 + (3 - pace) * (pace + 1))
        for _ in 0..<3 * (3 - pace) { animation.step() }
        #expect(animation.wagonFrame == 3)
    }

    @Test func lowerStripWrapsBeforeTheNextMovement() {
        var animation = OriginalTravelAnimation(input: input(pace: 2))
        for _ in 0..<175 { animation.step() }
        #expect(animation.lowerStripX == 65)
        animation.step()
        #expect(animation.lowerStripX == -457)
    }

    @Test func adaptiveLandmarkUsesMeasuredTicksAndLastMovement() {
        var value = input(remaining: 40)
        value.lastMovement = 20
        var animation = OriginalTravelAnimation(input: value)
        animation.step(tick: 100)
        #expect(animation.landmark.x == 89 && animation.landmark.left == 89)
        #expect(animation.landmark.duration == 48 && animation.landmark.delta == 30)
        animation.step(tick: 103)
        #expect(animation.landmark.x == 89 && animation.landmark.averageTicks == 4)
        value.remainingMiles = 20
        animation.apply(value)
        #expect(animation.landmark.x == 89) // Input updates do not teleport artwork.
        animation.step(tick: 106)
        #expect(animation.landmark.x == 90)
        #expect(animation.landmark.duration == 80 && animation.landmark.delta == 70)
        animation.step(tick: 1000)
        #expect(animation.landmark.totalTicks == 26 && animation.landmark.averageTicks == 6)
    }

    @Test func wagonStopsOneUpdateAfterStripsAtVisualArrivalEdge() {
        var animation = OriginalTravelAnimation(input: input(pace: 2, remaining: 1))
        animation.step(tick: 0)
        #expect(animation.wagonFrame == 4 && animation.lowerStripX == -457)
        animation.step(tick: 3)
        #expect(animation.landmark.x == 208 && animation.wagonFrame == 5)
        #expect(animation.lowerStripX == -457)
        animation.step(tick: 6)
        #expect(animation.wagonFrame == 5 && animation.input.remainingMiles == 1)
    }

    @Test func immediateJumpPreservesOldFixedPointAndCorrectionKeepsFivePixelOffset() {
        var value = input(remaining: 100)
        value.lastMovement = 20
        var animation = OriginalTravelAnimation(input: value)
        animation.step(tick: 0)
        animation.step(tick: 3)
        value.remainingMiles = 30
        animation.apply(value)
        animation.step(tick: 6)
        #expect(animation.landmark.duration == 0 && animation.landmark.delta == 70)
        #expect(animation.landmark.x == -90 && animation.landmark.left == -90)
        var motion = animation.landmark
        motion.previousX = 100
        motion.advance(input: value, tick: 9, endTick: 9)
        #expect(motion.x == 105 && motion.left == 100)
        motion.advance(input: value, tick: 12, endTick: 12)
        #expect(motion.x == 110 && motion.left == 105)
    }

    @Test func nextLegIncreaseReselectsFrameWithoutResettingScrollingStrips() {
        var animation = OriginalTravelAnimation(input: input(remaining: 1))
        animation.step(tick: 0)
        animation.apply(input(destination: 2, remaining: 90))
        let lowerBefore = animation.lowerStripX
        animation.step(tick: 3)
        #expect(animation.landmarkFrame == 8)
        #expect(animation.landmark.y == 47)
        #expect(animation.lowerStripX == lowerBefore + 1)
    }

    @Test func paletteSeasonAndWeatherRules() {
        #expect(OriginalTravelAnimation(input: input(destination: 4)).palette.groundSource == 228)
        #expect(OriginalTravelAnimation(input: input(destination: 5, month: 6)).palette.groundSource == 228)
        #expect(OriginalTravelAnimation(input: input(destination: 14, month: 3)).palette.groundSource == 226)
        #expect(OriginalTravelAnimation(input: input(snow: 1)).palette.groundSource == 227)
        let sky = (0..<10).map { OriginalTravelAnimation(input: input(weather: $0)).palette.skySource }
        #expect(sky == [230,230,232,232,231,231,231,231,231,231])
    }

    @Test func paletteReplacementPreservesSharedRGBIndices() throws {
        var table = [UInt8](repeating: 0, count: 256 * 3)
        for index in [226,229] { table.replaceSubrange(index*3..<index*3+3, with: [63,255,0]) }
        table.replaceSubrange(227*3..<227*3+3, with: [245,248,238])
        table.replaceSubrange(231*3..<231*3+3, with: [156,191,212])
        let space = try #require(CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: 255, colorTable: &table))
        let bytes = Data([226,229,233])
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let source = try #require(CGImage(width: 3, height: 1, bitsPerComponent: 8,
            bitsPerPixel: 8, bytesPerRow: 3, space: space, bitmapInfo: [], provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let result = try #require(OriginalTravelPalette.replacing(in: source,
            with: .init(groundSource: 227, skySource: 231)))
        let colors = try #require(result.colorSpace?.colorTable)
        #expect(Array(colors[226*3..<226*3+3]) == [63,255,0])
        #expect(Array(colors[229*3..<229*3+3]) == [245,248,238])
        #expect(Array(colors[233*3..<233*3+3]) == [156,191,212])
        #expect(result.dataProvider?.data as Data? == bytes)
    }
}
