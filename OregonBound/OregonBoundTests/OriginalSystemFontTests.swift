import XCTest
@testable import OregonBound

final class OriginalSystemFontTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    func testChicagoControlTitleMetrics() throws {
        let font = try XCTUnwrap(BitmapFont.chicago12)
        XCTAssertEqual(font.width("Move"), 36)
        XCTAssertEqual(font.width("Stop Hunting"), 83)
        XCTAssertEqual(font.width("Travel the Trail"), 98)
        XCTAssertEqual(font.lineHeight, 16)
        XCTAssertEqual(font.layout("A").glyphs.first?.rect, CGRect(x: 1, y: 0, width: 6, height: 15))
    }

    func testGenevaStrikesHaveIndependentMetrics() throws {
        let nine = try XCTUnwrap(BitmapFont.geneva9)
        let twelve = try XCTUnwrap(BitmapFont.geneva12)
        XCTAssertEqual(nine.width("Move"), 24)
        XCTAssertEqual(twelve.width("Move"), 30)
        XCTAssertEqual(nine.lineHeight, 12)
        XCTAssertEqual(twelve.lineHeight, 16)
    }

    func testMacRomanCodesBeyondSystemStrikeUseMissingGlyph() throws {
        for font in [try XCTUnwrap(BitmapFont.chicago12), try XCTUnwrap(BitmapFont.geneva9), try XCTUnwrap(BitmapFont.geneva12)] {
            // Mac Roman byte255 is encodable but outside all three strikes.
            let character = try XCTUnwrap(String(data: Data([255]), encoding: .macOSRoman))
            let missing = font.metrics.glyphs[font.metrics.missing_glyph_index]
            XCTAssertEqual(font.width(character), missing.advance)
            XCTAssertEqual(font.width("🐂"), missing.advance)
            XCTAssertEqual(font.layout(character).glyphs.count, 1)
        }
    }
}
