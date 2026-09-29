import Testing
@testable import OregonBound

struct OriginalHuntPresentationTests {
    @Test func preparationLastsThirtyActiveMacTicksAndDoesNotCatchUpAfterHiding() {
        var ready = OriginalHuntPreparation()
        ready.advance(to: 100,active: true)
        for tick in 101...129 { ready.advance(to: tick, active: true) }
        #expect(!ready.isReady && ready.remainingTicks == 1)
        ready.advance(to: 130,active: true)
        #expect(ready.isReady)
        var hidden = OriginalHuntPreparation()
        hidden.advance(to: 100,active: true)
        hidden.advance(to: 110,active: true)
        hidden.advance(to: 120,active: false)
        hidden.advance(to: 1000,active: true)
        #expect(hidden.remainingTicks == 29)
        for tick in 1001...1029 { hidden.advance(to: tick, active: true) }
        #expect(hidden.isReady)
    }
    @Test(.enabled(if: GameData.isReady)) func originalCursorMaskUsesOpaqueBlackAndWhiteAndTransparentExterior() {
        let pixels = OriginalHuntCursor.rgba
        #expect(pixels.count == 16*16*4)
        guard pixels.count == 1024 else { return }
        #expect(Array(pixels[0..<4]) == [0,0,0,0])
        #expect(Array(pixels[7*4..<8*4]) == [0,0,0,255])
        #expect(Array(pixels[5*4..<6*4]) == [255,255,255,255])
        #expect(pixels.enumerated().filter { $0.offset%4 == 3 && $0.element == 255 }.count == 132)
    }
}
