import Foundation
import Testing
@testable import OregonBound

struct OriginalJourneySimulationTests {
    private func prepared() -> Journey {
        var trip = Journey(names: ["Sierra", "Anna", "Jed", "Zeke", "Mary"], seed: 42)
        trip.phase = .travel
        trip.inventory[.oxen] = 12
        trip.inventory[.food] = 1000
        trip.inventory[.clothing] = 10
        trip.original?.weather.initialized = true
        trip.original?.weather.category = 128 // explicit dry event override, no weather draws
        trip.original?.weather.temperature = 2
        trip.original?.flags = 6 // previous rest ends today; pre-event flags suppress events
        return trip
    }

    @Test func departureJournalMatchesOriginalPurchaseExample() throws {
        var trip = Journey(seed: 42)
        try JourneyEngine.completeOutfitting([.oxen: 6, .clothing: 10, .bullets: 100,
                                            .wheels: 1, .axles: 1, .tongues: 1, .food: 1000], in: &trip)
        try JourneyEngine.chooseDeparture(month: 4, in: &trip)
        #expect(trip.inventory[.oxen] == 12 && trip.displayQuantity(.oxen) == 6)
        #expect(trip.journal.map(\.text) == ["You started down the trail with 6 oxen, 10 sets of clothing, 100 bullets, 1 wagon wheel, 1 wagon axle, 1 wagon tongue, 1,000 pounds of food, and $1,140.00."])
        try JourneyEngine.depart(&trip)
        #expect(trip.journal.last?.text == "You decided to continue.")
    }

    @Test func productionTravelMatchesOriginalSixDisplayedOxenArrival() {
        var trip = prepared()
        for day in 1...6 {
            // Isolate deterministic days, as original day entry after rest does.
            trip.original?.weather.category = 128
            trip.original?.flags = 6
            JourneyEngine.advanceDay(&trip)
            #expect(trip.daysElapsed == day)
            #expect(trip.miles == min(20 * day, 102))
        }
        #expect(trip.phase == .river)
        #expect(trip.locationID == "kansas")
        #expect(trip.inventory[.food] == 910)
        #expect(trip.dateText == "April 7, 1848")
    }

    @Test func finalPoundUsesFedFormulaAndMembersShareTheBand() {
        var trip = prepared()
        trip.inventory[.food] = 1
        JourneyEngine.advanceDay(&trip)
        #expect(trip.healthBadness == 2)
        #expect(trip.inventory[.food] == 0)
        trip.original?.weather.category = 128
        trip.original?.flags = 6
        JourneyEngine.advanceDay(&trip)
        #expect(trip.healthBadness == 20) // old2*.9 + starvation16 + pace2 + auxiliary1
        #expect(Set(trip.livingMembers.map(\.health)).count == 1)
    }

    @Test func recoveringTodayStillSlowsMovement() {
        var trip = prepared()
        trip.members[2].illness = "Typhoid"
        trip.members[2].sickDays = 1
        JourneyEngine.advanceDay(&trip)
        #expect(trip.miles == 18) //20 *9/10, truncation after full product
        #expect(trip.members[2].illness == nil)
        #expect(trip.journal.contains { $0.text == "Jed is well again." })
    }

    @Test func restAndDelayCountersClearOnFollowingDay() throws {
        var trip = prepared()
        trip.original?.flags = 2
        OriginalTrailEvents.delay(1, in: &trip)
        JourneyEngine.advanceDay(&trip)
        #expect(trip.delayDays == 0)
        #expect(trip.miles == 0)
        #expect(trip.original!.flags & 8 != 0)
        trip.original?.weather.category = 128
        JourneyEngine.advanceDay(&trip)
        #expect(trip.miles == 20)
        #expect(trip.original!.flags & 8 == 0)
        let before = trip.miles
        JourneyEngine.pauseTravel(in: &trip)
        try JourneyEngine.rest(days: 2, in: &trip)
        #expect(trip.miles == before)
        #expect(trip.original?.restDays == 0)
    }

    @Test(arguments: [34,35,69,70,104,105,139])
    func scoringUsesSharedBadness(raw: Int) {
        var trip = prepared()
        trip.won = true
        trip.original?.badness = UInt8(raw)
        let people = JourneyEngine.scoreLines(trip).first { $0.id == "People arriving" }
        #expect(people?.points == 5 * (500 - raw/35*100))
    }

    @Test func legacySaveMigratesOnceAndFutureRandomnessRoundTrips() throws {
        var legacy = prepared()
        legacy.original = nil
        legacy.inventory[.oxen] = 6
        for index in legacy.members.indices { legacy.members[index].health = 50 }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "original")
        object.removeValue(forKey: "inventoryUnitsVersion")
        let data = try JSONSerialization.data(withJSONObject: object)
        var trip = try JSONDecoder().decode(Journey.self, from: data)
        #expect(trip.original == nil)
        trip.ensureOriginalState()
        #expect(trip.healthBadness == 35)
        #expect(trip.inventory[.oxen] == 12 && trip.displayQuantity(.oxen) == 6)
        #expect(trip.original?.weather.initialized == true)
        var resumed = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        for _ in 0..<3 {
            JourneyEngine.advanceDay(&trip)
            JourneyEngine.advanceDay(&resumed)
        }
        #expect(trip == resumed)
    }

    @Test func legacySouthPassLegIsCorrectedWithoutLosingItsDestination() {
        var trip = prepared()
        trip.original = nil
        trip.locationID = "south-pass"
        trip.destinationID = "bridger"
        trip.legDistance = 125
        trip.legProgress = 20
        trip.ensureOriginalState()
        #expect(trip.legDistance == 57)
        #expect(trip.legProgress == 20)
        #expect(trip.destinationID == "bridger")
    }

    @Test func oxenPurchasesTradesCapacityAndScoringUseExplicitUnits() throws {
        var trip = prepared()
        trip.phase = .landmark
        let oldCash = trip.cash
        try JourneyEngine.buy(.oxen, quantity: 2, in: &trip)
        #expect(trip.inventory[.oxen] == 16 && trip.displayQuantity(.oxen) == 8)
        #expect(trip.cash == oldCash - 4000)
        trip.won = true
        #expect(JourneyEngine.scoreLines(trip).first { $0.id == "Oxen" }?.points == 32)
        trip.won = false
        try JourneyEngine.trade(give: .food, quantity: 150, receive: .oxen, in: &trip)
        #expect(trip.inventory[.oxen] == 18) // UI1 pair, raw2, value ratio unchanged
        trip.inventory[.oxen] = 40
        #expect(throws: GameRuleError.self) { try JourneyEngine.buy(.oxen, quantity: 1, in: &trip) }
        #expect(Supply.oxen.purchaseCapacity == 20)
        trip.inventory[.oxen] = 3
        #expect(trip.displayQuantity(.oxen) == 2) // original ceiling display
    }

    @Test func migrationPreservesLegacyAboveOriginalOxenLimit() throws {
        var trip = prepared()
        trip.inventoryUnitsVersion = nil
        trip.inventory[.oxen] = 40
        trip.ensureOriginalState()
        #expect(trip.inventory[.oxen] == 80)
        #expect(trip.displayQuantity(.oxen) == 40)
        #expect(trip.legacyOxenLimit == 80)
        try JourneyStore().validate(trip)
    }

    @Test func invalidOriginalStateIsRejectedBySaveValidation() {
        var trip = prepared()
        trip.original?.weather.region = 6
        #expect(throws: GameRuleError.self) { try JourneyStore().validate(trip) }
    }

    @Test func weatherRetainsOppositeIncrementAndStrictMeltBoundary() {
        var state = OriginalDailyWeather.State()
        state.category = 3; state.rain = 100; state.snow = 1000
        state.rainIncrement = 20; state.snowIncrement = 160
        OriginalDailyWeather.update(&state, month: 3) { bound in
            #expect(bound == 2)
            return 0
        }
        #expect(state.rain == 110 && state.snow == 1130)
        state.category = 128; state.temperature = 3
        state.rain = 0; state.snow = 516
        state.rainIncrement = 0; state.snowIncrement = 0
        OriginalDailyWeather.update(&state, month: 3) { _ in Issue.record("Unexpected weather draw"); return 0 }
        #expect(state.rain == 50 && state.snow == 500)
    }
}
