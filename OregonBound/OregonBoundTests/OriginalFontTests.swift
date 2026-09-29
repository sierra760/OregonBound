import XCTest
@testable import OregonBound

final class OriginalFontTests: XCTestCase {
    override func setUpWithError() throws { try GameDataTestSupport.requireGameData() }

    func testOriginalWelcomeHeadingUsesRecoveredStrike() throws {
        let font = try XCTUnwrap(BitmapFont.bold14)
        XCTAssertEqual(font.width("Welcome to The Oregon Trail!"), 201)
        XCTAssertEqual(font.lineHeight, 15)
        XCTAssertEqual(font.layout("Welcome to The Oregon Trail!").size.height, 15)
    }

    func testWelcomeWrapMatchesObservedOriginalRightEdge() throws {
        let font = try XCTUnwrap(BitmapFont.bold14)
        let prefix = "You’re about to begin a great adventure, traveling the"
        XCTAssertEqual(font.width(prefix + " Oregon"), 419)
        let layout = font.layout(prefix + " Oregon", maxWidth: 419)
        XCTAssertEqual(layout.size.height, 30)
        let lastLine = layout.glyphs.filter { $0.rect.minY == 15 }
        XCTAssertEqual(lastLine.count, 6)
        XCTAssertEqual(lastLine.first?.rect.minX, 0)
    }

    func testMissingUnicodeUsesOriginalFallbackGlyph() throws {
        let font = try XCTUnwrap(BitmapFont.bold14)
        let layout = font.layout("🐂")
        let fallback = font.metrics.glyphs[font.metrics.missing_glyph_index]
        XCTAssertEqual(layout.size.width, CGFloat(try XCTUnwrap(fallback.advance)))
        XCTAssertEqual(layout.glyphs.count, 1)
    }

    func testJournalMeasurementsUseMacRomanBytesAndOriginalLineHeight() throws {
        for font in [try XCTUnwrap(BitmapFont.plain12), try XCTUnwrap(BitmapFont.bold12)] {
            let text = "André • wagon…"
            let bytes = try XCTUnwrap(text.data(using: .macOSRoman))
            let widths = try XCTUnwrap(font.prefixWidths(text))
            XCTAssertEqual(widths.count, bytes.count + 1)
            XCTAssertEqual(widths[0], 0)
            for count in 1...bytes.count {
                let prefix = try XCTUnwrap(String(data: bytes.prefix(count), encoding: .macOSRoman))
                XCTAssertEqual(widths[count], font.width(prefix))
            }
            XCTAssertEqual(font.lineHeight, 12)
            XCTAssertNil(font.prefixWidths("🐂"))
        }
    }

    func testSystemScrollbarPartsAreBundledAtOriginalPixelDimensions() throws {
        for down in [false, true] {
            for enabled in [false, true] {
                for pressed in [false, true] {
                    let arrow = try XCTUnwrap(OriginalScrollbarArtwork.arrow(down: down, pressed: pressed, enabled: enabled))
                    XCTAssertEqual(arrow.width, 16)
                    XCTAssertEqual(arrow.height, 16)
                }
            }
        }
        XCTAssertEqual(try XCTUnwrap(OriginalScrollbarArtwork.thumb).width, 14)
        XCTAssertEqual(try XCTUnwrap(OriginalScrollbarArtwork.thumb).height, 16)
        XCTAssertEqual(try XCTUnwrap(OriginalScrollbarArtwork.track).width, 8)
        XCTAssertEqual(try XCTUnwrap(OriginalScrollbarArtwork.track).height, 8)
    }

    func testDepartureWrappingMatchesCapturedOriginalJournal() throws {
        // docs/reference/original-guide-index.png and original-kansas.png.
        let font = try XCTUnwrap(BitmapFont.plain12)
        let text = try XCTUnwrap(OriginalJournalRules.supplyEvent(id: 68,
            rawQuantities: [12,10,100,1,1,1,1000], cashCents: 114000))
        let layout = try OriginalJournalLayout.layout(text: text,
            prefixWidths: XCTUnwrap(font.prefixWidths(text)))
        XCTAssertEqual(layout.fragments.map { $0.drawingText.trimmingCharacters(in: .whitespaces) }, [
            "You started down the trail with 6 oxen, 10 sets of",
            "clothing, 100 bullets, 1 wagon wheel, 1 wagon",
            "axle, 1 wagon tongue, 1,000 pounds of food,",
            "and $1,140.00."
        ])
        XCTAssertEqual(layout.fragments.map(\.x), [3,15,15,15])
        XCTAssertFalse(layout.wasTruncated)
    }

    func testNativeLinefeedsUseSeparateBitmapRowsInsteadOfOverlappingOriginalFragments() throws {
        let font = try XCTUnwrap(BitmapFont.plain12)
        let text = "First line\nSecond line"
        XCTAssertNil(font.journalRecordLayout(text, isBold: false))
        XCTAssertEqual(font.layout(text, maxWidth: 241).size.height, 24)
        let original = try XCTUnwrap(font.journalRecordLayout("First line\rSecond line", isBold: false))
        XCTAssertEqual(original.fragments.count, 2)
        XCTAssertTrue(original.fragments.allSatisfy { font.layout($0.drawingText).size.height == 12 })
    }
}
