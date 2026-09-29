import XCTest
@testable import OregonBound

final class OriginalMapTests: XCTestCase {
    func testFirstLegPaintsFourOffsetsWithIntegerTruncation() {
        XCTAssertEqual(OriginalMap.paintedCount(path: 0, destination: 0, remaining: 82, flags: 0, count: 72), 0)
        XCTAssertEqual(OriginalMap.paintedCount(path: 0, destination: 0, remaining: 62, flags: 0, count: 72), 1)
        XCTAssertEqual(OriginalMap.paintedCount(path: 0, destination: 0, remaining: 0, flags: 0, count: 72), 4)
        XCTAssertEqual(OriginalMap.paintedCount(path: 2, destination: 0, remaining: 0, flags: 0, count: 19), 0)
    }
    func testPathsJoinAtOriginalResourceBoundaries() {
        XCTAssertEqual(OriginalMap.paintedCount(path: 0, destination: 6, remaining: 0, flags: 0, count: 72), 72)
        XCTAssertEqual(OriginalMap.paintedCount(path: 2, destination: 9, remaining: 0, flags: 0, count: 19), 19)
        XCTAssertEqual(OriginalMap.paintedCount(path: 3, destination: 13, remaining: 0, flags: 0, count: 37), 37)
        XCTAssertEqual(OriginalMap.paintedCount(path: 5, destination: 15, remaining: 0, flags: 0, count: 15), 15)
    }
    func testSkippedFortPreservesOriginalInheritedRegisterBehavior() {
        XCTAssertEqual(OriginalMap.distance(8, flags: 1, path: 1), 1)
        XCTAssertEqual(OriginalMap.paintedCount(path: 1, destination: 8, remaining: 100, flags: 1, count: 11), 3)
        XCTAssertEqual(OriginalMap.paintedCount(path: 1, destination: 9, remaining: 0, flags: 1, count: 11), 11)
        XCTAssertEqual(OriginalMap.distance(15, flags: 2, path: 4), 4)
        XCTAssertEqual(OriginalMap.paintedCount(path: 4, destination: 15, remaining: 100, flags: 2, count: 12), 12)
    }
}
