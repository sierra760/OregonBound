import Testing
@testable import OregonBound

struct OriginalHuntSettlementTests {
    @Test func liveFoodAndMileageButStartupCarryLimitSurviveInterleavedRest() throws {
        var trip = Journey(names: ["A", "B"], seed: 42)
        trip.phase = .travel
        trip.destinationID = "big-blue"; trip.locationID = "kansas"; trip.legDistance = 83; trip.legProgress = 20
        trip.inventory[.food] = 1750; trip.inventory[.bullets] = 50
        trip.miles = 123
        try JourneyEngine.beginHunt(&trip)
        trip.members[1].health = 0
        let oldSnapshot = OriginalHuntSession.Result(foodShot: 350, foodCarried: 0, shots: 1,
                                                     lastSuccessfulHuntMileage: 120, carryLimit: 200)
        let settled = try JourneyEngine.finishHunt(result: oldSnapshot, in: &trip)
        #expect(settled.foodCarried == 200)
        #expect(trip.inventory[.food] == 1950)
        #expect(trip.original?.lastSuccessfulHuntMileage == 123)
        #expect(settled.carryLimit == 200)
        #expect(trip.journal.last?.text == "You brought back 200 pounds of food from hunting.")
    }

    @Test func multiPersonCarryAndRestQueueAreAppliedBeforeOutcomeDialog() throws {
        var trip = Journey(seed: 1234)
        trip.phase = .travel
        trip.inventory[.food] = 1000
        trip.inventory[.bullets] = 50
        trip.miles = 102
        trip.destinationID = "big-blue"; trip.locationID = "kansas"; trip.legDistance = 83; trip.legProgress = 0
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.finishHunt(food: 350, shots: 2, in: &trip)
        #expect(trip.inventory[.food] == 1200)
        #expect(trip.inventory[.bullets] == 48)
        #expect(trip.original?.lastSuccessfulHuntMileage == 102)
        #expect(trip.original?.restDays == 1 && trip.original!.flags & 4 != 0)
        #expect(trip.phase == .travel && trip.daysElapsed == 0 && trip.randomState == 1234)
        #expect(trip.journal.last?.text == "You brought back 200 pounds of food from hunting.")
    }
    @Test func fullWagonStillMarksSuccessfulAreaAndSoloCarryIsOneHundred() throws {
        var trip = Journey(names: ["Alone"], seed: 42)
        trip.phase = .travel
        trip.inventory[.food] = Supply.food.capacity
        trip.inventory[.bullets] = 50
        trip.miles = 55
        trip.destinationID = "kansas"; trip.legDistance = 102; trip.legProgress = 55
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.finishHunt(food: 250, shots: 1, in: &trip)
        #expect(trip.inventory[.food] == Supply.food.capacity)
        #expect(trip.original?.lastSuccessfulHuntMileage == 55)
        #expect(trip.journal.last?.text == "You brought back 0 pounds of food from hunting.")
        trip.phase = .travel
        trip.inventory[.food] = 0
        try JourneyEngine.beginHunt(&trip)
        try JourneyEngine.finishHunt(food: 250, shots: 1, in: &trip)
        #expect(trip.inventory[.food] == 100)
    }
}
