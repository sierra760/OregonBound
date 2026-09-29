import XCTest
@testable import OregonBound

final class OriginalWagonContinuationTests: XCTestCase {
    func testReplacementsAreInstalledWithoutTimeRandomnessOrMessages() {
        var trip = Journey(seed: 123)
        trip.inventory[.oxen] = 12
        for part in [Supply.wheels, .axles, .tongues] {
            trip.markBroken(part)
            trip.inventory[part] = 2
        }
        XCTAssertNil(OriginalWagonContinuation.prepare(&trip))
        XCTAssertTrue(trip.damagedParts.isEmpty)
        XCTAssertEqual([trip.inventory[.wheels], trip.inventory[.axles], trip.inventory[.tongues]], [1, 1, 1])
        XCTAssertEqual(trip.daysElapsed, 0)
        XCTAssertEqual(trip.randomState, 123)
        XCTAssertTrue(trip.journal.isEmpty)
    }
    func testNoOxenReturnsBeforeInstallingAnyReplacement() {
        var trip = Journey(seed: 1)
        trip.markBroken(.wheels)
        trip.inventory[.wheels] = 1
        XCTAssertEqual(OriginalWagonContinuation.prepare(&trip), .oxen)
        XCTAssertEqual(trip.damagedParts, [.wheels])
        XCTAssertEqual(trip.inventory[.wheels], 1)
    }
    func testEarlierReplacementPersistsWhileLastMissingPartBlocks() {
        var trip = Journey(seed: 1)
        trip.inventory[.oxen] = 1
        for part in [Supply.wheels, .axles, .tongues] { trip.markBroken(part) }
        trip.inventory[.wheels] = 1
        XCTAssertEqual(OriginalWagonContinuation.prepare(&trip), .tongues)
        XCTAssertEqual(trip.damagedParts, [.axles, .tongues])
        XCTAssertEqual(trip.inventory[.wheels], 0)
    }
}
