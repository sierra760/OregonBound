import Foundation
import Testing
@testable import OregonBound

struct OriginalHealthTests {
    @Test func cdDustStormSurvivesDailyHealthAndSaveReload() throws {
        var input = OriginalHealth.Input()
        input.edition = .macintoshCD12; input.weather = 10
        #expect(OriginalHealth.transition(input).terms.paceAndWeather == 4)
        input.stateFlags = 8
        #expect(OriginalHealth.transition(input).terms.paceAndWeather == 2)

        var trip = Journey(seed: 51, edition: .macintoshCD12)
        trip.phase = .landmark
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        trip.original?.weather.initialized = true
        trip.original?.weather.category = 0x8a
        trip.original?.weather.rain = 4
        try JourneyEngine.beginRest(days: 1, in: &trip)
        let seed = trip.randomState
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.original?.weather.category == 10)
        #expect(trip.weather == .storm)
        #expect(trip.randomState == seed)
        #expect(trip.totalFood == 985)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12)
        try store.save(trip)
        #expect(try store.load() == trip)
    }

    @Test(arguments: [0, 1, 2]) func cdConsumesBothFoodPoolsAndCoversEitherShortfall(rations: Int) {
        var input = OriginalHealth.Input()
        input.edition = .macintoshCD12
        input.rations = UInt8(rations)
        for survivors in 1...5 {
        input.survivors = UInt8(survivors)
        let need = survivors * (3 - rations)
        for (stored, fresh) in [(100,100), (0,100), (100,0), (1,1), (0,0)] {
            input.food = Int16(stored); input.perishableFood = Int16(fresh)
            let output = OriginalHealth.transition(input)
            let storedShare = need / 5, freshShare = need - storedShare
            #expect(Int(output.food) == max(0, stored - storedShare - max(0, freshShare - fresh)))
            #expect(Int(output.perishableFood) == max(0, fresh - freshShare - max(0, storedShare - stored)))
            #expect(output.terms.rations == (stored + fresh > 0 ? 2*rations : 16))
        }
        }
    }

    @Test func perishableOnlyFoodPreventsStarvationAndClassicIgnoresSecondPool() {
        var input = OriginalHealth.Input()
        input.food = 0; input.perishableFood = 100; input.edition = .macintoshCD12
        let cd = OriginalHealth.transition(input)
        #expect(cd.food == 0 && cd.perishableFood == 85)
        #expect(cd.terms.rations == 0 && cd.auxiliary == 0)
        input.edition = .macintosh11
        let classic = OriginalHealth.transition(input)
        #expect(classic.food == 0 && classic.perishableFood == 100)
        #expect(classic.terms.rations == 16 && classic.auxiliary == 1)
    }

    @Test func cdDailyNeedsAndSaveReloadKeepPoolsSeparate() throws {
        var trip = Journey(seed: 1234, edition: .macintoshCD12)
        trip.phase = .travel; trip.locationID = "kansas"; trip.destinationID = "big-blue"; trip.legDistance = 83
        trip.inventory[.food] = 100; trip.inventory.perishableFood = 100
        trip.inventory[.oxen] = 6; trip.inventory[.clothing] = 10
        try JourneyEngine.beginRest(days: 1, in: &trip)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.inventory[.food] == 97 && trip.inventory.perishableFood == 88)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12)
        try store.save(trip)
        let loaded = try store.load()
        #expect(loaded.inventory == trip.inventory && loaded.totalFood == 185)
    }

    @Test func foodInventoryDecodesOldSavesAndValidatesPerishableLimit() throws {
        let old = Data(#"{"quantities":{"food":2000}}"#.utf8)
        var inventory = try JSONDecoder().decode(Inventory.self, from: old)
        #expect(inventory.perishableFood == 0 && inventory[.food] == 2000)
        inventory.perishableFood = 1000
        #expect(inventory.valid)
        #expect(try JSONDecoder().decode(Inventory.self, from: JSONEncoder().encode(inventory)) == inventory)
        let bad = Data(#"{"quantities":{"perishableFood":1001}}"#.utf8)
        #expect(try !JSONDecoder().decode(Inventory.self, from: bad).valid)
        var trip = Journey(seed: 1234, edition: .macintosh11)
        trip.inventory.perishableFood = 1
        #expect(throws: GameRuleError.self) { try JourneyStore(edition: .macintosh11).validate(trip) }
    }

    @Test(arguments: [0, 34, 35, 69, 70, 104, 105, 139])
    func originalBandsAndPersonScores(_ raw: Int) {
        let badness = UInt8(raw)
        #expect(OriginalHealth.band(for: badness)?.rawValue == raw / 35)
        #expect(OriginalHealth.scorePerSurvivor(badness: badness) == 500 - (raw / 35) * 100)
    }

    @Test func lastPoundStillUsesTheSelectedRationPenalty() {
        var input = OriginalHealth.Input()
        input.food = 1
        let lastFood = OriginalHealth.transition(input)
        #expect(lastFood.food == 0)
        #expect(lastFood.badness == 2)
        input.food = 0
        let starving = OriginalHealth.transition(input)
        #expect(starving.badness == 19)
        #expect(starving.auxiliary == 1)
    }

    @Test(arguments: [UInt8(4), UInt8(8)])
    func restingAndDelayedRetainWeatherAndRationPenalties(_ flags: UInt8) {
        var input = OriginalHealth.Input()
        input.badness = 50
        input.pace = 2
        input.stateFlags = flags
        input.weather = 5
        input.rations = 2
        let output = OriginalHealth.transition(input)
        #expect(output.badness == 51) // 45 retained +2 snow +4 bare bones
        #expect(output.food == 95)
        #expect(output.terms.paceAndWeather == 2)
    }

    @Test func auxiliaryNegativeNumeratorTruncatesTowardZero() {
        var input = OriginalHealth.Input()
        #expect(OriginalHealth.transition(input).auxiliary == 0)
        input.auxiliary = 5
        #expect(OriginalHealth.transition(input).auxiliary == 2)
    }

    @Test func thresholdIsStrictlyGreaterThan139() {
        var input = OriginalHealth.Input()
        input.pendingEventPenalty = 137 // steady2 +137 =139
        #expect(!OriginalHealth.transition(input).thresholdCrossed)
        input.pendingEventPenalty = 138
        let output = OriginalHealth.transition(input)
        #expect(output.storedBadnessBeforeThreshold == 140)
        #expect(output.thresholdCrossed)
        #expect(output.badness == 139)
    }

    @Test func byteWrapOccursBeforeTheThresholdComparison() {
        var input = OriginalHealth.Input()
        input.pendingEventPenalty = 255
        let output = OriginalHealth.transition(input)
        #expect(output.terms.sum == 257)
        #expect(output.storedBadnessBeforeThreshold == 1)
        #expect(output.badness == 1)
        #expect(!output.thresholdCrossed)
        #expect(output.pendingEventPenalty == 0)
    }

    @Test func oldBadnessIsCappedBeforeDecay() {
        var input = OriginalHealth.Input()
        input.badness = 255
        input.stateFlags = 4
        #expect(OriginalHealth.transition(input).badness == 125)
        #expect(OriginalHealth.band(for: 140) == nil)
    }

    @Test func recoveryDayStillAddsAConditionPenaltyAndTimerWraps() {
        var input = OriginalHealth.Input()
        input.members = [
            .init(condition: 255, remainingDays: 0),
            .init(condition: 4, remainingDays: 1),
            .init(condition: 9, remainingDays: 0),
            .init(condition: 2, remainingDays: 0)
        ]
        let output = OriginalHealth.transition(input)
        #expect(output.terms.activeConditions == 2)
        #expect(output.recoveredMemberIndices == [1])
        #expect(output.members[1].condition == 255)
        #expect(output.members[3].remainingDays == 255)
        #expect(output.members[2].condition == 9)
    }

    @Test func clothingDivisionUsesTheSurvivingCount() {
        var input = OriginalHealth.Input()
        input.temperature = 0
        input.clothing = 14
        let output = OriginalHealth.transition(input)
        #expect(output.terms.clothing == 3) // 5 -0 -floor(14/5)
        #expect(output.badness == 8) // cold2 +clothing3 +pace2 +aux1
    }
}
