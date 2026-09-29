import Foundation
import Testing
@testable import OregonBound

@Suite(.enabled(if: GameData.isReady))
struct OriginalStaticTextLayoutTests {
    private func layout(_ text: String, width: Int, centered: Bool = false,
                        font: BitmapFont? = .bold14) throws -> [OriginalStaticTextLayout.Line] {
        let font = try #require(font)
        return try OriginalStaticTextLayout.lines(bytes: Array(text.data(using: .macOSRoman)!),
            prefixWidths: try #require(font.prefixWidths(text)), width: width,
            lineHeight: font.lineHeight, centered: centered)
    }

    @Test func crossingCaptionUsesIntegerTextBoxCenterAndCaretIndent() throws {
        #expect(try layout("Crossing the river…", width: 256, centered: true) == [
            .init(start: 0, end: 19, x: 61, y: 0)
        ])
    }

    @Test func failureHeadingUsesFastLeftPlacementWithoutVerticalCentering() throws {
        let text = "Your wagon tipped over while crossing the river."
        #expect(try layout(text, width: 242, font: .plain12) == [
            .init(start: 0, end: 48, x: 1, y: 0)
        ])
    }

    @Test func safeResultUsesFullAuthoredWidthForTextEditWrapping() throws {
        #expect(try layout("You made it safely across the river.", width: 236) == [
            .init(start: 0, end: 30, x: 1, y: 0),
            .init(start: 30, end: 36, x: 1, y: 15)
        ])
    }

    @Test func centeredWrappedLineIncludesTrailingSpaceInItsMeasuredWidth() throws {
        #expect(try layout("You made it safely across the river.", width: 236, centered: true) == [
            .init(start: 0, end: 30, x: 17, y: 0),
            .init(start: 30, end: 36, x: 99, y: 15)
        ])
    }
}
