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

    @Test(arguments: [3, 4, 11, 12])
    func cdDustStormBoundariesPrecedeTemperature(destination: Int) {
        for edition in [GameEdition.macintosh11, .macintoshCD12] {
            for (rain, snow) in [(4,0), (5,0), (4,1)] {
                for temperature in [0,2,5] {
                    var trip = Journey(seed: 42, edition: edition)
                    trip.destinationID = TrailCatalog.stops[destination + 1].id
                    trip.original?.weather.rain = UInt16(rain)
                    trip.original?.weather.snow = UInt16(snow)
                    trip.original?.weather.temperature = UInt8(temperature)
                    let dust = edition == .macintoshCD12 && rain < 5 && snow == 0 && (4...11).contains(destination)
                    let rng = Draws([])
                    OriginalTrailEvents.apply(.severeWeather, to: &trip, draw: rng.next)
                    #expect(rng.sites.isEmpty)
                    let category: UInt8 = dust ? 0x8a : temperature <= 1 ? 0x88 : temperature >= 4 ? 0x87 : 0
                    #expect(trip.original?.weather.category == category)
                    #expect(trip.delayDays == (category == 0 ? 0 : 1))
                    if dust { #expect(trip.journal.last?.text == "Dust Storm.") }
                }
            }
        }
    }

    @Test func cdDustStormRunsThroughNormalDispatchWithoutExtraDraws() {
        var trip = Journey(seed: 42, edition: .macintoshCD12)
        trip.inventory[.food] = 1000
        trip.destinationID = TrailCatalog.stops[5].id
        trip.original?.weather.temperature = 1
        trip.original?.weather.rain = 4
        let rng = Draws([99,0,99,99,99,99,99])
        OriginalTrailEvents.run(&trip, draw: rng.next)
        #expect(trip.original?.weather.category == 0x8a)
        #expect(trip.journal.last?.text == "Dust Storm.")
        #expect(rng.sites == [0x312c,0x3200,0x3216,0x322c,0x32a0,0x32de,0x3320])
        #expect(rng.values.isEmpty)
    }

    @Test func dustOverrideLastsOneWeatherUpdateAndDoesNotAddPrecipitation() {
        var state = OriginalDailyWeather.State()
        state.category = 0x8a; state.rain = 4; state.temperature = 1
        OriginalDailyWeather.update(&state, month: 4) { _ in Issue.record("Override must not draw"); return 0 }
        #expect(state.category == 10 && state.rain == 3 && state.snow == 0)
        #expect(state.rainIncrement == 0 && state.snowIncrement == 0)
        var bounds: [Int] = []
        OriginalDailyWeather.update(&state, month: 4) { bound in bounds.append(bound); return bound - 1 }
        #expect(bounds == [3,41,1000])
        #expect(state.category == 2)
        #expect(OriginalHuntEligibility.evaluate(weatherCategory: 10, milesRemaining: 80, ammunition: 100) == .severeWeather)
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
        var values: [Int] = [99,99,roll] + (selected ? [1] : []) + [99]
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
    @Test(arguments: [(2,9,false), (3,9,true), (3,10,false)])
    func cdWarmWeatherSpoilageRunsBetweenSnakebiteAndIllness(input: (Int,Int,Bool)) {
        let (temperature, roll, spoils) = input
        var trip = prepared(); trip.edition = .macintoshCD12
        trip.inventory.perishableFood = 201
        trip.original?.weather.temperature = UInt8(temperature)
        var sites: [Int] = []
        OriginalTrailEvents.run(&trip) { bound, site in
            sites.append(site)
            if site == 0x3be6 { return roll }
            return bound - 1
        }
        #expect(trip.inventory.perishableFood == (spoils ? 181 : 201))
        #expect(trip.inventory[.food] == 1000)
        #expect(sites.contains(0x3be6) == (temperature >= 3))
        if temperature >= 3 {
            #expect(sites.first == 0x30d6)
            #expect(sites[1] == 0x3be6)
            #expect(sites.contains(0x312c))
            if let spoilage = sites.firstIndex(of: 0x3be6), let illness = sites.firstIndex(of: 0x312c) {
                #expect(spoilage < illness)
            }
        }
        if spoils { #expect(trip.journal.last?.text == "You lost 20 pounds of perishable food due to spoilage.") }
    }

    @Test func cdFoodAidChecksBothPoolsAndFruitUsesPerishableCapacity() {
        var trip = prepared(); trip.edition = .macintoshCD12
        trip.inventory[.food] = 0; trip.inventory.perishableFood = 1
        OriginalTrailEvents.run(&trip) { bound, site in
            #expect(site != 0x3160)
            return bound - 1
        }
        trip.inventory.perishableFood = 0
        OriginalTrailEvents.run(&trip) { bound, site in site == 0x3160 ? 0 : bound - 1 }
        #expect(trip.inventory[.food] == 0 && trip.inventory.perishableFood == 30)
        trip.inventory[.food] = 2000; trip.inventory.perishableFood = 995
        OriginalTrailEvents.apply(.wildFruit, to: &trip, draw: Draws([]).next)
        #expect(trip.inventory[.food] == 2000 && trip.inventory.perishableFood == 1000)
        let count = trip.journal.count
        OriginalTrailEvents.apply(.wildFruit, to: &trip, draw: Draws([]).next)
        #expect(trip.journal.count == count)
    }

    @Test func cdFireIncludesPerishableSlotAndTheftUsesWholeDollars() {
        var trip = prepared(); trip.edition = .macintoshCD12
        trip.inventory.perishableFood = 100
        let fire = Draws([99,99,99,99,99,99,0,30])
        OriginalTrailEvents.apply(.fire, to: &trip, draw: fire.next)
        #expect(trip.inventory.perishableFood == 70 && trip.inventory[.food] == 1000)
        #expect(fire.values.isEmpty)
        #expect(trip.journal.last?.text == "A fire in your wagon destroyed 30 pounds of perishable food.")
        trip.inventory[.food] = 0; trip.cash = 550
        let thief = Draws([3,4])
        OriginalTrailEvents.apply(.thief, to: &trip, draw: thief.next)
        #expect(thief.bounds.last == 5)
        #expect(trip.cash == 50 && trip.inventory.perishableFood == 70)
    }

    @Test(arguments: [(2750,99,false), (2751,90,false), (2751,91,true), (2800,89,false), (2800,90,true)])
    func cdOverloadChecksUseWeightBeforeSpoilageAndStrictThreshold(input: (Int,Int,Bool)) {
        let (weight, roll, breaks) = input
        var trip = prepared(); trip.edition = .macintoshCD12
        for item in Supply.allCases { trip.inventory[item] = 0 }
        trip.inventory[.oxen] = 4; trip.inventory[.food] = 2000
        trip.inventory.perishableFood = weight - 2500
        trip.original?.weather.temperature = 3
        var sites: [Int] = []
        OriginalTrailEvents.run(&trip) { bound, site in
            sites.append(site)
            if site == 0x3be6 { return 0 } // Spoilage must not change this day's cached load.
            if site == 0x324e { return roll }
            if [0x2b68,0x2b76,0x2bb2,0x2bea].contains(site) { return 0 }
            if site == 0x33ea { return 0 }
            return bound - 1
        }
        #expect((trip.brokenPart == .wheels) == breaks)
        #expect(sites.contains(0x324e) == (weight > 2750))
        #expect(sites.contains(0x33ea) == (weight > 2750))
        #expect(trip.inventory[.oxen] == 4)
    }

    @Test(arguments: [0,1]) func cdRandomBreakageSkipsOnlyItsCorrespondingOverloadCheck(selected: Int) {
        var trip = prepared(); trip.edition = .macintoshCD12
        trip.inventory[.food] = 2000; trip.inventory.perishableFood = 1000
        var sites: [Int] = []
        OriginalTrailEvents.run(&trip) { bound, site in
            sites.append(site)
            if site == 0x322c { return 0 }
            if site == 0x326c { return selected }
            if [0x324e,0x33ea].contains(site) { return 0 }
            return bound - 1
        }
        #expect(sites.contains(0x324e) == (selected != 0))
        #expect(sites.contains(0x33ea) == (selected != 1))
    }

}
