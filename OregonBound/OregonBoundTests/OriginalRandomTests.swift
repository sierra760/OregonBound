import XCTest
@testable import OregonBound

final class OriginalRandomTests: XCTestCase {
    func testQuickDrawKnownSequence() {
        var random = OriginalRandom(seed: 1)
        let seeds: [UInt32] = [16807, 282475249, 1622650073, 984943658, 1144108930,
                               470211272, 101027544, 1457850878, 1458777923, 2007237709]
        let results = [16807, 15089, -21287, 3114, -18558, -9528, -28968, 2558, 12099, 1101]
        for (seed, result) in zip(seeds, results) {
            XCTAssertEqual(random.next(), result)
            XCTAssertEqual(random.seed, seed)
        }
    }

    func testNegative32768ReturnsZeroWithoutClearingSeed() {
        var random = OriginalRandom(seed: 958682087)
        XCTAssertEqual(random.next(), 0)
        XCTAssertEqual(random.seed, 32768)
    }

    func testUnsignedSeedAndZeroAreNotReplaced() {
        var zero = OriginalRandom(seed: 0)
        XCTAssertEqual(zero.next(), 0)
        XCTAssertEqual(zero.seed, 0)
        var high = OriginalRandom(seed: .max)
        XCTAssertEqual(high.next(), 16807)
        XCTAssertEqual(high.seed, 16807)
    }

    func testGameBoundedWrapperConsumesOnlyNontrivialDraws() {
        var random = OriginalRandom(seed: 1)
        XCTAssertEqual(random.bounded(0), 0)
        XCTAssertEqual(random.bounded(1), 0)
        XCTAssertEqual(random.seed, 1)
        XCTAssertEqual(random.bounded(2), 1)
        XCTAssertEqual(random.bounded(1000), 89)
        XCTAssertEqual(random.bounded(1000), 287)
        XCTAssertEqual(random.seed, 1622650073)
    }
}
