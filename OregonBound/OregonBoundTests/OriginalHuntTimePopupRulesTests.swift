import XCTest
@testable import OregonBound
final class OriginalHuntTimePopupRulesTests: XCTestCase {
    typealias Rules = OriginalHuntTimePopupRules
    func testCODE15ClosedBoxAndOnlyBoxStartsTracking() {
        XCTAssertEqual(Rules.box,.init(x:86,y:130,width:108,height:20))
        var state = Rules.State()
        state.press(at:.init(x:13,y:140),selection:3)
        XCTAssertFalse(state.isTracking)
        state.press(at:.init(x:85,y:140),selection:3)
        XCTAssertFalse(state.isTracking)
        state.press(at:.init(x:86,y:130),selection:3)
        XCTAssertTrue(state.isTracking)
        XCTAssertEqual(state.highlightedItem,3)
    }
    func testMDEF0e24CurrentRowAlignedForAllSelections() {
        for selected in 1...6 {
            let rect = Rules.menuRect(selection:selected)
            XCTAssertEqual(rect.width,97)
            XCTAssertEqual(rect.height,96)
            XCTAssertEqual(rect.y+(selected-1)*16,130)
            XCTAssertEqual(Rules.item(at:.init(x:100,y:130),selection:selected),selected)
        }
    }
    func testMDEF0234HalfOpenRowsAndMenuEdges() {
        XCTAssertEqual(Rules.item(at:.init(x:86,y:50),selection:6),1)
        XCTAssertEqual(Rules.item(at:.init(x:182,y:65),selection:6),1)
        XCTAssertEqual(Rules.item(at:.init(x:182,y:66),selection:6),2)
        XCTAssertNil(Rules.item(at:.init(x:183,y:66),selection:6))
        XCTAssertNil(Rules.item(at:.init(x:100,y:146),selection:6))
        XCTAssertNil(Rules.item(at:.init(x:100,y:49),selection:6))
    }
    func testCODE1519b0CommitChangedPositiveChoiceOnly() {
        var state = Rules.State()
        state.press(at:.init(x:100,y:130),selection:3)
        state.drag(to:.init(x:100,y:98))
        XCTAssertEqual(state.highlightedItem,1)
        XCTAssertEqual(state.release(at:.init(x:100,y:98)),1)
        XCTAssertFalse(state.isTracking)
        XCTAssertNil(state.release(at:.init(x:100,y:98)))
        state.press(at:.init(x:100,y:130),selection:3)
        XCTAssertNil(state.release(at:.init(x:100,y:130)))
        state.press(at:.init(x:100,y:130),selection:3)
        state.drag(to:.init(x:200,y:140))
        XCTAssertNil(state.highlightedItem)
        XCTAssertNil(state.release(at:.init(x:200,y:140)))
    }
}
