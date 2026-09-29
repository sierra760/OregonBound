import Testing
@testable import OregonBound

struct OriginalClassicScrollBarColorsTests {
    @Test func disabledBarAndTrackUseRecoveredDifferentGrayFamilies() {
        #expect(OriginalClassicScrollBarColors.color(32).rgba8 == [238,238,238,255])
        #expect(OriginalClassicScrollBarColors.color(33).rgba8 == [221,221,221,255])
        #expect(OriginalClassicScrollBarColors.color(28).rgba8 == [119,119,119,255])
        #expect(OriginalClassicScrollBarColors.color(22).rgba8 == [221,221,221,255])
    }
    @Test func interpolationRetainsOriginalMultiplyHighWordResidual() {
        let low = OriginalClassicScrollBarColors.color(14)
        let end = OriginalClassicScrollBarColors.color(37)
        #expect(end.red == low.red+1 && end.green == low.green+1 && end.blue == low.blue+1)
        #expect(OriginalClassicScrollBarColors.color(34).rgba8 == [204,204,255,255])
        #expect(end.rgba8 == [51,51,102,255])
    }
    @Test func explicitControlOverridesDoNotSilentlyRecolorUnrelatedGroups() {
        let override = [1: OriginalClassicScrollBarColors.gamePaper]
        #expect(OriginalClassicScrollBarColors.color(1,overrides: override).rgba8 == [255,246,137,255])
        #expect(OriginalClassicScrollBarColors.color(35,overrides: override) == OriginalClassicScrollBarColors.color(35))
        let custom = OriginalClassicScrollBarColors.RGB16(red: 65535,green: 0,blue: 0)
        #expect(OriginalClassicScrollBarColors.color(34,overrides: [13:custom]) == custom)
    }
    @Test func indexedDeviceCanSelectMonochromeDespiteEightBitDepth() {
        #expect(!OriginalClassicScrollBarColors.usesColor(pixelDepth:2) { _ in 0 })
        #expect(!OriginalClassicScrollBarColors.usesColor(pixelDepth:8) { _ in 3 })
        #expect(OriginalClassicScrollBarColors.usesColor(pixelDepth:8) { rgb in
            UInt32(rgb.red) << 16 | UInt32(rgb.blue)
        })
        // Preserve grays but collapse all blues: third probe group rejects it.
        #expect(!OriginalClassicScrollBarColors.usesColor(pixelDepth:8) { rgb in
            rgb.red == rgb.blue ? UInt32(rgb.red) : 3
        })
    }
    @Test func patternIsPortAlignedAndRepeatsForNegativeCoordinates() {
        let foreground = OriginalClassicScrollBarColors.color(28)
        let background = OriginalClassicScrollBarColors.color(22)
        #expect(OriginalClassicScrollBarColors.trackColor(x:0,y:0) == foreground)
        #expect(OriginalClassicScrollBarColors.trackColor(x:1,y:0) == background)
        #expect(OriginalClassicScrollBarColors.trackColor(x:2,y:1) == foreground)
        #expect(OriginalClassicScrollBarColors.trackColor(x:-6,y:-7) == foreground)
        #expect(OriginalClassicScrollBarColors.trackColor(x:10,y:9) == foreground)
    }
}
