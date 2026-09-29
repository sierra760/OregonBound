import XCTest
@testable import OregonBound

final class OriginalSetupTests: XCTestCase {
    func testObservedOriginalPurchaseThenMonthSelection() throws {
        var trip = Journey(seed: 42)
        try JourneyEngine.completeOutfitting([.oxen: 6, .clothing: 10, .bullets: 100,
                                             .wheels: 1, .axles: 1, .tongues: 1, .food: 1000], in: &trip)
        // Recorded directly in original-purchase.png: total $460, balance $1,140.
        XCTAssertEqual(trip.cash, 114_000)
        XCTAssertEqual(trip.inventory[.bullets], 100)
        XCTAssertEqual(trip.phase, .departure)
        try JourneyEngine.chooseDeparture(month: 4, in: &trip)
        XCTAssertEqual(trip.departureMonth, 4)
        XCTAssertEqual(trip.daysElapsed, 0)
        XCTAssertEqual(trip.phase, .landmark)
        XCTAssertEqual(trip.locationID, "independence")
    }

    func testCartFailureDoesNotPartiallyChargePlayer() throws {
        var trip = Journey(profession: .farmer, seed: 42)
        let original = trip
        XCTAssertThrowsError(try JourneyEngine.completeOutfitting([.oxen: 20, .food: 2000], in: &trip))
        XCTAssertEqual(trip, original)
    }

    func testOriginalSouthPassRoutesAndLandmarkScenes() {
        let routes = TrailCatalog.stop("south-pass").routes
        XCTAssertEqual(routes.first(where: { $0.destination == "bridger" })?.miles, 57)
        XCTAssertEqual(routes.first(where: { $0.destination == "green" })?.miles, 125)
        XCTAssertEqual(TrailCatalog.stop("kearney").image, 15300)
        XCTAssertEqual(TrailCatalog.stop("kearney").frame, 1)
        XCTAssertEqual(TrailCatalog.stop("dalles").image, 15306)
        XCTAssertEqual(TrailCatalog.stop("dalles").frame, 0)
        XCTAssertEqual(dollars(114000), "$1,140.00")
    }
}
