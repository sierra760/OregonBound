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

    func testBothEditionsRequireStartingOxenAndFoodWithoutMutatingSetup() {
        for edition in [GameEdition.macintosh11, .macintoshCD12] {
            for cart: [Supply: Int] in [[:], [.food: 10], [.oxen: 1]] {
                var trip = Journey(seed: 42, edition: edition)
                let before = trip
                XCTAssertThrowsError(try JourneyEngine.completeOutfitting(cart, in: &trip)) { error in
                    XCTAssertEqual(error.localizedDescription,
                        "Matt says: You can’t set off on the trail without any oxen or food.")
                }
                XCTAssertEqual(trip, before)
            }
        }
    }

    func testStartingCartChecksMoneyBeforeCapacityButKeepsRowOrder() {
        for edition in [GameEdition.macintosh11, .macintoshCD12] {
            // Missing food in the last row cannot override an earlier row's error.
            for (cash, expected): (Int, OriginalStoreRules.Rejection) in [
                (0, .insufficientMoney), (160_000, .capacity(item: 0, quantity: 21))
            ] {
                var trip = Journey(seed: 42, edition: edition); trip.cash = cash
                let before = trip
                XCTAssertThrowsError(try JourneyEngine.completeOutfitting([.oxen: 21], in: &trip)) {
                    XCTAssertEqual($0 as? OriginalStoreRules.Rejection, expected)
                }
                XCTAssertEqual(trip, before)
            }
        }
    }

    func testStartingCartRequiresWholeBulletBoxesAndAllowsExactBalance() throws {
        for edition in [GameEdition.macintosh11, .macintoshCD12] {
            var trip = Journey(seed: 42, edition: edition)
            let before = trip
            XCTAssertThrowsError(try JourneyEngine.completeOutfitting([.oxen: 1, .food: 1, .bullets: 1], in: &trip))
            XCTAssertEqual(trip, before)
            trip.cash = 2220
            try JourneyEngine.completeOutfitting([.oxen: 1, .food: 1, .bullets: 20], in: &trip)
            XCTAssertEqual(trip.phase, .departure)
            XCTAssertEqual(trip.cash, 0)
            XCTAssertEqual(trip.inventory[.oxen], 2)
            XCTAssertEqual(trip.inventory[.food], 1)
            XCTAssertEqual(trip.inventory[.bullets], 20)
            XCTAssertEqual(trip.inventory.perishableFood, 0)
            XCTAssertEqual(trip.randomState, before.randomState)
            XCTAssertEqual(trip.daysElapsed, before.daysElapsed)
        }
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
