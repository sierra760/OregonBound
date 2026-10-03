import XCTest
@testable import OregonBound

final class OriginalGuideTests: XCTestCase {

    func testInitialTopicMatchesOriginalLandmarkMapping() {
        XCTAssertEqual(OriginalGuide(locationID: "independence").page, 33)
        XCTAssertEqual(OriginalGuide(locationID: "kansas").page, 37)
        XCTAssertEqual(OriginalGuide(locationID: "south-pass").page, 54)
        // A topic-name lookup would incorrectly choose Blue Mountains (page 9).
        XCTAssertEqual(OriginalGuide(locationID: "blue-mountains").page, 30)
        XCTAssertEqual(OriginalGuide(locationID: "oregon").page, 61)
    }

    func testIndexCancelKeepsCurrentPageAndOKAppliesSelection() {
        var guide = OriginalGuide(locationID: "independence")
        guide.openIndex()
        XCTAssertTrue(guide.showingIndex)
        XCTAssertEqual(guide.selection, 33)
        XCTAssertEqual(guide.initialIndexRow, 32)
        guide.select(57)
        guide.closeIndex(accept: false)
        XCTAssertEqual(guide.page, 33)
        XCTAssertFalse(guide.showingIndex)
        guide.openIndex()
        XCTAssertEqual(guide.selection, 33)
        guide.select(57)
        guide.closeIndex(accept: true)
        XCTAssertEqual(guide.page, 57)
        XCTAssertFalse(guide.showingIndex)
    }

    func testPageTurnsStopAtBookEndsAndCrossResourceBoundaries() {
        var guide = OriginalGuide(locationID: "unknown")
        guide.turn(forward: false)
        XCTAssertEqual(guide.page, 1)
        XCTAssertEqual(guide.pageLabel, " 1 of 61")
        for _ in 0..<2 { guide.turn(forward: true) }
        XCTAssertEqual(guide.textResource, 3151)
        XCTAssertEqual(guide.textResourceEntry, 3)
        guide.turn(forward: true)
        XCTAssertEqual(guide.textResource, 3152)
        XCTAssertEqual(guide.textResourceEntry, 1)
        for _ in 0..<70 { guide.turn(forward: true) }
        XCTAssertEqual(guide.page, 61)
        XCTAssertEqual(guide.textResource, 3171)
        XCTAssertEqual(guide.textResourceEntry, 1)
        XCTAssertEqual(guide.pageLabel, "61 of 61")
        guide.openIndex()
        XCTAssertEqual(guide.initialIndexRow, 50)
    }

    func testDiagonalControlHitDirectionMatchesCDEF8() {
        XCTAssertTrue(OriginalGuide.turnsForward(x: 3, y: 25))
        XCTAssertFalse(OriginalGuide.turnsForward(x: 25, y: 3))
        XCTAssertFalse(OriginalGuide.turnsForward(x: 16, y: 16))
    }

    func testIndependenceUsesEightOriginalTextLines() throws {
        try GameDataTestSupport.requireGameData()
        XCTAssertEqual(OriginalResources.guide.count, 61)
        let entry = try XCTUnwrap(OriginalResources.guide.first { $0.id == 32 })
        XCTAssertEqual(entry.title, "Independence, Missouri")
        let font = try XCTUnwrap(BitmapFont.plain12)
        XCTAssertEqual(font.layout(entry.text, maxWidth: 230).size.height, 96)
        XCTAssertEqual(OriginalGuide.indexBitmap.count, 35)
    }
}
