import XCTest
@testable import OregonBound

final class JourneyTests: XCTestCase {
    func testVerifiedOriginalSupplyAndOccupationTables() {
        XCTAssertEqual(Supply.allCases.map(\.capacity), [40, 50, 1980, 3, 3, 3, 2000])
        XCTAssertEqual(Profession.allCases.map(\.startingCash), [160000, 80000, 80000, 120000, 40000, 120000, 80000, 40000])
    }

    func testOriginalScoreUsesYokesAndHalfStepOccupationBonus() {
        let factors = [2, 4, 4, 2, 6, 3, 5, 7]
        for (index, profession) in Profession.allCases.enumerated() {
            for difficulty in Difficulty.allCases {
                var trip = Journey(profession: profession, difficulty: difficulty, names: ["Traveler"], seed: 1)
                trip.won = true
                trip.cash = 0
                trip.inventory[.oxen] = 3
                trip.inventory[.bullets] = 50
                // One healthy person 500 + wagon 50 + two yokes 8 + ammunition 1.
                XCTAssertEqual(JourneyEngine.score(trip), (559 * factors[index] + 1) / 2)
                trip.won = false
                XCTAssertEqual(JourneyEngine.score(trip), 0)
            }
        }
    }

    func testOriginalFortPricesChargeAmmunitionByTheBox() throws {
        var trip = Journey(seed: 1)
        trip.phase = .landmark
        trip.locationID = "kearney"
        let cash = trip.cash
        try JourneyEngine.buy(.bullets, quantity: 20, in: &trip)
        XCTAssertEqual(trip.cash, cash - 250)
        trip.locationID = "boise"
        let nextCash = trip.cash
        try JourneyEngine.buy(.food, quantity: 100, in: &trip)
        XCTAssertEqual(trip.cash, nextCash - 4500)
    }

    func outfitted(seed: UInt32 = 42) throws -> Journey {
        var trip = Journey(profession: .banker, difficulty: .greenhorn, names: ["Sierra", "Anna", "Jed", "Zeke", "Mary"], departureMonth: 4, seed: seed)
        for (item, quantity) in [(Supply.oxen, 6), (.food, 1000), (.clothing, 10), (.bullets, 100), (.wheels, 2), (.axles, 2), (.tongues, 2)] {
            try JourneyEngine.buy(item, quantity: quantity, in: &trip)
        }
        try JourneyEngine.depart(&trip)
        return trip
    }

    func testCannotDepartWithoutFoodAndOxen() {
        var trip = Journey(seed: 42)
        XCTAssertThrowsError(try JourneyEngine.depart(&trip))
        XCTAssertEqual(trip.phase, .outfitting)
    }

    func testPurchasesAreAtomicAndRejectNegativeOrUnaffordableAmounts() throws {
        var trip = Journey(seed: 42)
        let original = trip
        XCTAssertThrowsError(try JourneyEngine.buy(.food, quantity: -10, in: &trip))
        XCTAssertEqual(trip, original)
        XCTAssertThrowsError(try JourneyEngine.buy(.oxen, quantity: 99, in: &trip))
        XCTAssertEqual(trip, original)
        try JourneyEngine.buy(.bullets, quantity: 20, in: &trip)
        XCTAssertEqual(trip.inventory[.bullets], 20)
        XCTAssertEqual(trip.cash, original.cash - 200)
    }

    func testTravelAdvancesDateDistanceAndConsumesFood() throws {
        var trip = try outfitted()
        JourneyEngine.advanceDay(&trip)
        XCTAssertEqual(trip.daysElapsed, 1)
        XCTAssertGreaterThan(trip.miles, 0)
        XCTAssertLessThan(trip.inventory[.food], 1000)
        XCTAssertEqual(trip.members.count, 5)
    }

    func testStopsExactlyAtRiverAndRequiresCrossing() throws {
        var trip = try outfitted()
        for _ in 0..<30 where trip.phase == .travel { JourneyEngine.advanceDay(&trip) }
        XCTAssertEqual(trip.phase, .river)
        XCTAssertEqual(trip.locationID, "kansas")
        XCTAssertEqual(trip.miles, 102)
        let snapshot = trip
        JourneyEngine.advanceDay(&trip)
        XCTAssertEqual(trip, snapshot)
        // This seeded Kansas arrival is below 2.5 feet: ferry is visible but
        // selection must fail; the original shallow ford crosses safely.
        XCTAssertLessThan(trip.riverDepth, 2.5)
        XCTAssertThrowsError(try JourneyEngine.cross(.ferry, in: &trip))
        try JourneyEngine.cross(.ford, in: &trip)
        XCTAssertEqual(trip.phase, .landmark)
        try JourneyEngine.depart(&trip)
        XCTAssertEqual(trip.phase, .travel)
    }

    func testRestConsumesFoodAndTimeWithoutMoving() throws {
        var trip = try outfitted()
        trip.original?.badness = 70
        trip.synchronizeSharedHealth()
        let distance = trip.miles
        JourneyEngine.pauseTravel(in: &trip) // Time Out preserves a stopped rest.
        try JourneyEngine.rest(days: 3, in: &trip)
        XCTAssertEqual(trip.daysElapsed, 4) // original counter-zero cleanup day
        XCTAssertEqual(trip.miles, distance)
        XCTAssertLessThan(trip.inventory[.food], 1000)
        XCTAssertLessThan(trip.healthBadness, 70)
        XCTAssertEqual(Set(trip.livingMembers.map(\.health)).count, 1)
    }

    func testStarvationEndsGameEvenWhenCashAndAmmunitionRemain() throws {
        var trip = try outfitted()
        trip.inventory[.food] = 0
        for _ in 0..<40 where trip.phase != .finished { try JourneyEngine.rest(days: 1, in: &trip) }
        XCTAssertEqual(trip.phase, .finished)
        XCTAssertFalse(trip.won)
        XCTAssertEqual(trip.livingMembers.count, 0)
        let snapshot = trip
        JourneyEngine.advanceDay(&trip)
        XCTAssertEqual(trip, snapshot)
    }

    func testSaveRoundTripPreservesFutureRandomEvents() throws {
        var first = try outfitted()
        JourneyEngine.advanceDay(&first)
        var resumed = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(first))
        for _ in 0..<4 {
            JourneyEngine.advanceDay(&first)
            JourneyEngine.advanceDay(&resumed)
        }
        XCTAssertEqual(first, resumed)
    }

    func testHuntSettlementIsAppliedOnceAndCapped() throws {
        var trip = try outfitted()
        trip.legProgress = 20; trip.miles = 20
        trip.original?.weather.category = 0
        try JourneyEngine.beginHunt(&trip)
        let oldFood = trip.inventory[.food]
        try JourneyEngine.finishHunt(food: 900, shots: 4, in: &trip)
        XCTAssertEqual(trip.inventory[.food], oldFood + 200)
        XCTAssertEqual(trip.inventory[.bullets], 96)
        let snapshot = trip
        XCTAssertThrowsError(try JourneyEngine.finishHunt(food: 900, shots: 4, in: &trip))
        XCTAssertEqual(trip, snapshot)
    }
}
