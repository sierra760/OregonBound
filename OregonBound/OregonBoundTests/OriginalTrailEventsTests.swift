import Foundation
import Testing
@testable import OregonBound

struct OriginalTrailEventsTests {
    private final class Draws {
        var values: [Int]
        var sites: [Int] = []
        var bounds: [Int] = []
        init(_ values: [Int]) { self.values = values }
        func next(_ bound: Int, _ site: Int) -> Int {
            sites.append(site); bounds.append(bound)
            if bound <= 1 { return 0 }
            precondition(!values.isEmpty, "Missing scripted draw at \(String(site, radix: 16))")
            let value = values.removeFirst()
            precondition((0..<bound).contains(value))
            return value
        }
    }

    private func prepared() -> Journey {
        var trip = Journey(seed: 42)
        trip.phase = .travel
        trip.inventory[.oxen] = 12
        trip.inventory[.clothing] = 10
        trip.inventory[.bullets] = 100
        trip.inventory[.wheels] = 1
        trip.inventory[.axles] = 1
        trip.inventory[.tongues] = 1
        trip.inventory[.food] = 1000
        trip.original?.weather.initialized = true
        trip.original?.weather.temperature = 2
        trip.original?.weather.rain = 1
        return trip
    }

    @Test func independentChecksInterleaveHelperDrawsAndTakeMaximumDelay() {
        var trip = prepared()
        trip.original?.weather.snow = 3001
        let rng = Draws([9, 99, 99, 99, 0, 4, 1, 99, 99])
        OriginalTrailEvents.run(&trip, draw: rng.next)
        #expect(rng.sites == [0x354a,0x312c,0x3216,0x322c,0x32a0,0x3064,0x3078,0x32de,0x3320])
        #expect(trip.delayDays == 10 && trip.original!.flags & 8 != 0)
        #expect(trip.journal.map(\.text) == ["Heavy snow has rendered your wagon snowbound.", "You’ve lost the trail."])
        #expect(rng.values.isEmpty)
    }

    @Test(arguments: [(11,3,true), (11,4,false), (12,6,true), (12,7,false)])
    func breakageThresholds(input: (Int, Int, Bool)) {
        let (destination, roll, selected) = input
        var trip = prepared()
        trip.destinationID = TrailCatalog.stops[destination + 1].id
        var values = [99,99,roll] + (selected ? [1] : []) + [99]
        if destination > 11 { values.append(99) }
        values += [99,99]
        let rng = Draws(values)
        OriginalTrailEvents.run(&trip, draw: rng.next)
        #expect(trip.inventory[.oxen] == (selected ? 11 : 12))
        #expect(rng.values.isEmpty)
    }

    @Test func weatherOverrideAvoidsColdCheckAndFeedsSameDayWeather() {
        var trip = prepared()
        trip.original?.weather.temperature = 4
        trip.original?.weather.category = 4
        let rng = Draws([4,99,99,99,99,99,99])
        OriginalTrailEvents.run(&trip, draw: rng.next)
        #expect(!rng.sites.contains(0x3200))
        #expect(trip.original?.weather.category == 0x87 && trip.delayDays == 1)
        #expect(trip.journal.last?.text == "Severe storm.")
        var weather = trip.original!.weather
        OriginalDailyWeather.update(&weather, month: trip.month) { _ in Issue.record("Override must not draw"); return 0 }
        #expect(weather.category == 7 && weather.rainIncrement == 100)
    }

    @Test func pendingHealthIsAssignedAndSnowSuppressesWater() {
        var trip = prepared()
        trip.original?.pendingEventPenalty = 99
        OriginalTrailEvents.apply(.roughImpassable, to: &trip, draw: Draws([1]).next)
        #expect(trip.original?.pendingEventPenalty == 10)
        OriginalTrailEvents.apply(.dryGround, to: &trip, draw: Draws([40]).next)
        #expect(trip.original?.pendingEventPenalty == 20)
        OriginalTrailEvents.apply(.dryGround, to: &trip, draw: Draws([60]).next)
        #expect(trip.original?.pendingEventPenalty == 10)
        trip.original?.weather.snow = 1
        let count = trip.journal.count
        OriginalTrailEvents.apply(.dryGround, to: &trip, draw: Draws([40]).next)
        #expect(trip.journal.count == count)
        OriginalTrailEvents.apply(.dryGround, to: &trip, draw: Draws([39]).next)
        #expect(trip.journal.last?.text == "No grass for the oxen.")
    }

    @Test func rawOxSicknessParityAndWanderingDoesNotLoseOxen() {
        var trip = prepared()
        OriginalTrailEvents.apply(.sickOx, to: &trip, draw: Draws([]).next)
        #expect(trip.inventory[.oxen] == 11 && trip.displayQuantity(.oxen) == 6)
        OriginalTrailEvents.apply(.sickOx, to: &trip, draw: Draws([]).next)
        #expect(trip.inventory[.oxen] == 10 && trip.displayQuantity(.oxen) == 5)
        OriginalTrailEvents.apply(.wanderedOx, to: &trip, draw: Draws([2]).next)
        #expect(trip.inventory[.oxen] == 10 && trip.delayDays == 3)
        #expect(trip.journal.map(\.text) == ["An ox is sick.", "An ox died.", "An ox wandered off."])
    }

    @Test func threeRepairDrawsBeforeSpareAndMultipleDamageSurvivesSave() throws {
        var trip = prepared()
        let rng = Draws([0,1,1,0])
        OriginalTrailEvents.apply(.brokenPart, to: &trip, draw: rng.next)
        #expect(rng.sites == [0x2d12,0x2b68,0x2b76,0x2bb2,0x2bea])
        #expect(trip.inventory[.wheels] == 0 && trip.delayDays == 0 && trip.brokenPart == nil)
        trip.inventory[.axles] = 0
        OriginalTrailEvents.apply(.brokenPart, to: &trip, draw: Draws([0,0,0,0]).next)
        OriginalTrailEvents.apply(.brokenPart, to: &trip, draw: Draws([1,0,0,0]).next)
        #expect(trip.damagedParts == [.wheels,.axles] && trip.original!.flags & 2 == 0)
        let decoded = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(decoded.damagedParts == [.wheels,.axles])
        trip.inventory[.wheels] = 1
        #expect(throws: GameRuleError.self) { try JourneyEngine.repair(&trip) }
        #expect(trip.brokenPart == .axles && trip.damagedParts == [.axles])
    }

    @Test func foundSuppliesReportPrecapGainAndFireExcludesOxen() {
        var trip = prepared()
        trip.inventory[.clothing] = 50
        OriginalTrailEvents.apply(.suppliesFound, to: &trip, draw: Draws([1,2,1,39,0,0,0]).next)
        #expect(trip.inventory[.clothing] == 50 && trip.inventory[.bullets] == 159)
        #expect(trip.journal.last?.text == "You found 3 sets of clothing, and 59 bullets in an abandoned wagon.")
        OriginalTrailEvents.apply(.fire, to: &trip, draw: Draws([50,50,50,50,50,49,1000]).next)
        #expect(trip.inventory[.food] == 0 && trip.inventory[.oxen] == 12)
        #expect(trip.journal.last?.text == "A fire in your wagon destroyed 1,000 pounds of food.")
        let count = trip.journal.count
        OriginalTrailEvents.apply(.fire, to: &trip, draw: Draws([99,99,99,99,99,0]).next)
        #expect(trip.journal.count == count)
    }

    @Test func memberRetryPreservesOriginalThousandthDrawFallback() {
        var trip = prepared()
        trip.members[1].health = 0
        let successAtLimit = Draws(Array(repeating: 0, count: 999) + [1])
        #expect(OriginalTrailEvents.memberIndex(trip, draw: successAtLimit.next) == 0)
        #expect(successAtLimit.sites.count == 1000)
        let allDead = Draws(Array(repeating: 0, count: 1001))
        #expect(OriginalTrailEvents.memberIndex(trip, draw: allDead.next) == 0)
        #expect(allDead.sites.count == 1001)
    }

    @Test func injuryRetainsLongTimerAndIllnessUsesOriginalMessages() {
        var trip = prepared()
        trip.members[1].sickDays = 40
        OriginalTrailEvents.apply(.snakebite, to: &trip, draw: Draws([0,2]).next)
        #expect(trip.members[1].illness == OriginalHealth.conditionNames[2] && trip.members[1].sickDays == 40)
        OriginalTrailEvents.apply(.brokenLimb, to: &trip, draw: Draws([0,1,4]).next)
        #expect(trip.members[1].illness == OriginalHealth.conditionNames[1] && trip.members[1].sickDays == 40)
        OriginalTrailEvents.apply(.illness, to: &trip, draw: Draws([1,1,2]).next)
        #expect(trip.members[2].illness == OriginalHealth.conditionNames[4] && trip.members[2].sickDays == 11)
        #expect(trip.journal.last?.text == "Jed is sick with typhoid fever.")
        OriginalTrailEvents.apply(.illness, to: &trip, draw: Draws([1]).next)
        #expect(!trip.members[2].alive && trip.journal.last?.text == "Jed died of typhoid.")
    }

    @Test func literalThiefOxenConversionAndSmallCashOverdraftAreNotClamped() throws {
        var trip = prepared()
        OriginalTrailEvents.apply(.thief, to: &trip, draw: Draws([0,1]).next) // loss2 ->1 ->even0
        #expect(trip.inventory[.oxen] == 12 && trip.journal.isEmpty)
        OriginalTrailEvents.apply(.thief, to: &trip, draw: Draws([0,3]).next) // loss4 ->2raw
        #expect(trip.inventory[.oxen] == 10)
        trip.inventory[.food] = 0
        trip.cash = 10_000
        OriginalTrailEvents.apply(.thief, to: &trip, draw: Draws([3,9999]).next)
        #expect(trip.cash == -990_000 && trip.originalCashOverdraft == true)
        let store = JourneyStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(trip)
        #expect(try store.load().cash == -990_000)
        trip.cash = -990_001
        #expect(throws: GameRuleError.self) { try store.validate(trip) }
        trip.cash = -1; trip.originalCashOverdraft = nil
        #expect(throws: GameRuleError.self) { try store.validate(trip) }
    }

    @Test func productionDayUsesExactDispatcherSeedBeforeWeatherAndHealth() {
        var trip = prepared()
        var oracle = trip
        var random = OriginalRandom(seed: trip.randomState)
        OriginalTrailEvents.run(&oracle) { bound, _ in random.bounded(bound) }
        var state = oracle.original!
        OriginalDailyWeather.tickCounters(flags: &state.flags, rest: &state.restDays, delay: &oracle.delayDays)
        OriginalDailyWeather.update(&state.weather, month: trip.month) { random.bounded($0) }
        JourneyEngine.advanceDay(&trip)
        #expect(trip.randomState == random.seed)
        #expect(trip.original?.weather == state.weather)
    }
}
