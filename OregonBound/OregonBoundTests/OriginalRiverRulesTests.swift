import Foundation
import Testing
@testable import OregonBound

struct OriginalRiverRulesTests {
    private final class Draws {
        var values: [Int]
        var sites: [Int] = []
        init(_ values: [Int]) { self.values = values }
        func next(_ bound: Int, _ site: Int) -> Int {
            sites.append(site)
            if bound <= 1 { return 0 }
            precondition(!values.isEmpty, "Missing draw at \(String(site, radix: 16))")
            let value = values.removeFirst()
            precondition((0..<bound).contains(value))
            return value
        }
    }
    private let empty = Array(repeating: 0, count: 7)
    private func depth(_ halfFeet: Int) -> OriginalRiverRules.Dimensions {
        .init(depthHalfFeet: UInt8(halfFeet), widthTensFeet: 60)
    }

    @Test(arguments: [(0,2,600), (1,2,220), (8,40,400), (11,12,1000)])
    func dryArrivalBases(input: (Int, Int, Int)) {
        let (destination, halfFeet, width) = input
        let result = OriginalRiverRules.dimensions(destination: destination, rain: 0)
        #expect(Int(result.depthHalfFeet) == halfFeet && result.widthFeet == width)
    }

    @Test func arrivalUsesRainIntegerTruncationAndByteWrap() {
        #expect(OriginalRiverRules.dimensions(destination: 0, rain: 24).depthHalfFeet == 2)
        let result = OriginalRiverRules.dimensions(destination: 0, rain: 25)
        #expect(result.depthHalfFeet == 3 && result.widthFeet == 600)
        #expect(OriginalRiverRules.dimensions(destination: 0, rain: 100).widthFeet == 610)
        let extreme = OriginalRiverRules.dimensions(destination: 8, rain: 65535)
        #expect(extreme.depthHalfFeet == UInt8(truncatingIfNeeded: 40 + 65535 / 25))
        #expect(extreme.widthTensFeet == UInt8(truncatingIfNeeded: (400 + 65535 * 3 / 20) / 10))
    }

    @Test func originalChoiceVisibilityAndDepthCostBoundaries() {
        #expect(OriginalRiverRules.availableMethods(destination: 0) == [.ford,.caulk,.ferry])
        #expect(OriginalRiverRules.availableMethods(destination: 1) == [.ford,.caulk])
        #expect(OriginalRiverRules.availableMethods(destination: 11) == [.ford,.caulk,.guide])
        #expect(OriginalRiverRules.rejection(.caulk, destination: 0, depthHalfFeet: 2, cash: 500, clothing: 3) != nil)
        #expect(OriginalRiverRules.rejection(.caulk, destination: 0, depthHalfFeet: 3, cash: 500, clothing: 3) == nil)
        #expect(OriginalRiverRules.rejection(.ferry, destination: 0, depthHalfFeet: 4, cash: 500, clothing: 3) == "The ferry is not running today because the river is too shallow.")
        #expect(OriginalRiverRules.rejection(.ferry, destination: 0, depthHalfFeet: 5, cash: 499, clothing: 3) != nil)
        #expect(OriginalRiverRules.rejection(.ferry, destination: 0, depthHalfFeet: 5, cash: 500, clothing: 3) == nil)
        #expect(OriginalRiverRules.rejection(.guide, destination: 11, depthHalfFeet: 12, cash: 0, clothing: 2) != nil)
    }

    @Test func fordThresholdsDistinguishSafeWetAndSwamped() {
        for halfFeet in [4,5] {
            let r = OriginalRiverRules.resolve(method: .ford, destination: 0, dimensions: depth(halfFeet), rain: 0,
                                               inventory: empty, living: [true], draw: Draws([]).next)
            #expect(r.failureKind == 0 && r.status == (halfFeet == 5 ? 4 : 0))
        }
        let rng = Draws([99, 100])
        let r = OriginalRiverRules.resolve(method: .ford, destination: 0, dimensions: depth(6), rain: 0,
                                           inventory: empty, living: [true], draw: rng.next)
        #expect(r.failureKind == 1 && r.status == 1)
        #expect(rng.sites == [0x15a4,0x2296])
        #expect(r.presentationRandomTicks == 100)
    }

    @Test func shallowBigBlueMudIsNotFailedCrossingOrDayDelay() {
        let r = OriginalRiverRules.resolve(method: .ford, destination: 1, dimensions: depth(4), rain: 0,
                                           inventory: empty, living: [true], draw: Draws([39]).next)
        #expect(r.failureKind == 0 && r.status == 3 && r.presentationRandomTicks == nil)
        let boundary = OriginalRiverRules.resolve(method: .ford, destination: 1, dimensions: depth(4), rain: 0,
                                                  inventory: empty, living: [true], draw: Draws([40]).next)
        #expect(boundary.status == 0)
    }

    @Test func caulkAndFerryCurrentRiskStrictBoundaries() {
        let success = OriginalRiverRules.resolve(method: .caulk, destination: 0, dimensions: depth(5), rain: 0,
                                                 inventory: empty, living: [true], draw: Draws([15]).next)
        #expect(success.status == 0 && success.currentFactor == 3)
        let failed = OriginalRiverRules.resolve(method: .caulk, destination: 0, dimensions: depth(5), rain: 0,
                                                inventory: empty, living: [true], draw: Draws([14,0]).next)
        #expect(failed.status == 2)
        let low = OriginalRiverRules.resolve(method: .ferry, destination: 8, dimensions: depth(40), rain: 0,
                                             inventory: empty, living: [true], draw: Draws([]).next)
        #expect(low.status == 0 && low.currentFactor == 5)
        let medium = OriginalRiverRules.resolve(method: .ferry, destination: 8, dimensions: depth(40), rain: 100,
                                                inventory: empty, living: [true], draw: Draws([5]).next)
        #expect(medium.status == 0 && medium.currentFactor == 6)
        let high = OriginalRiverRules.resolve(method: .ferry, destination: 8, dimensions: depth(40), rain: 600,
                                              inventory: empty, living: [true], draw: Draws([10]).next)
        #expect(high.status == 0 && high.currentFactor == 11)
    }

    @Test func suppliesThenOxPairsThenCompanionsThenLeaderThenPresentation() {
        let rng = Draws([0,10, 99,1, 0,20, 89,90, 74,75, 9])
        let r = OriginalRiverRules.resolve(method: .ford, destination: 0, dimensions: depth(20), rain: 0,
                                           inventory: [3,10,0,1,0,0,20], living: [true,true,false], draw: rng.next)
        #expect(r.losses == [2,10,0,1,0,0,20])
        #expect(r.drownedMembers == [1])
        #expect(rng.sites == [0x1608,0x1626,0x1608,0x1626,0x1608,0x1626,
                              0x14ce,0x14ce,0x1564,0x15a4,0x2296])
    }

    @Test func guideChangesAnimationMethodAndPaymentLoopSetsSnakeRegister() {
        let shallow = OriginalRiverRules.resolve(method: .guide, destination: 11, dimensions: depth(4), rain: 0,
                                                 inventory: empty, living: [true], draw: Draws([32]).next)
        #expect(shallow.animationMethodRaw == 1 && shallow.status == 0)
        let deep = OriginalRiverRules.resolve(method: .guide, destination: 11, dimensions: depth(12), rain: 93,
                                              inventory: empty, living: [true], draw: Draws([1]).next)
        #expect(deep.animationMethodRaw == 2 && deep.currentFactor == 1 && deep.status == 0)
    }

    @Test func snakeCaulkInheritsSixRootPanelsAndLossHelperUsesDepth() {
        // CODE18:1176 handles index9, not Snake11. Root dispatcher D7=6.
        let below = OriginalRiverRules.resolve(method: .caulk, destination: 11, dimensions: depth(12), rain: 93,
                                               inventory: empty, living: [true], draw: Draws([0]).next)
        #expect(below.currentFactor == 0 && below.status == 0)
        let rng = Draws([4, 3, 1, 99])
        let at = OriginalRiverRules.resolve(method: .caulk, destination: 11, dimensions: depth(12), rain: 94,
                                            inventory: [0,1,0,0,0,0,0], living: [true], draw: rng.next)
        #expect(at.currentFactor == 1 && at.status == 2)
        // Loss helper initializes D7=12 => factor1 => supplies threshold2,
        // so roll3 loses nothing. Solo leader then rolls against threshold8.
        #expect(at.losses == empty && at.drownedMembers == [0])
        #expect(rng.sites == [0x042a,0x1608,0x15a4,0x2296])
    }

    @Test func animationBeginsWithOnlyRiskResolved() throws {
        var trip = Journey(seed: 1)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = .init(depthHalfFeet: 40, widthTensFeet: 40)
        trip.riverDepth = 20; trip.riverWidth = 400
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        let outcome = try #require(trip.originalRiverOutcome)
        #expect(outcome.status == 1)
        #expect(outcome.losses == [0, 0, 0, 0, 0, 0, 0])
        #expect(outcome.drownedMembers.isEmpty)
        #expect(outcome.presentationRandomTicks == nil)
        #expect(trip.randomState == 1) // Deep fording has no risk draw.
        let animation = trip
        #expect(JourneyEngine.completeCrossing(in: &trip) == nil)
        #expect(trip == animation) // An unprepared record cannot settle.
    }

    @Test func failedCrossingDefersLossAndDeathUntilCompletion() throws {
        var trip = Journey(seed: 1)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = .init(depthHalfFeet: 40, widthTensFeet: 40)
        trip.riverDepth = 20; trip.riverWidth = 400
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        let inventory = trip.inventory
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        let outcome = try #require(trip.originalRiverOutcome)
        #expect(outcome.phase == .animation && outcome.drownedMembers.isEmpty)
        #expect(trip.inventory == inventory && trip.livingMembers.count == trip.members.count)
        #expect(trip.phase == .river && trip.journal.count == 1)
        let pending = trip
        #expect(throws: GameRuleError.self) { try JourneyEngine.beginCrossing(.ford, in: &trip) }
        #expect(trip == pending)
        var restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        try JourneyStore().validate(restored)
        let prepared = try #require(JourneyEngine.prepareCrossingResult(in: &restored))
        #expect(prepared.drownedMembers.count == trip.members.count)
        #expect(JourneyEngine.completeCrossing(in: &restored) == prepared)
        #expect(restored.phase == .finished && restored.livingMembers.isEmpty)
        #expect(restored.inventory[.food] == 1000 - prepared.losses[6])
        #expect(restored.inventory[.oxen] == 0 && restored.daysElapsed == 0)
        let completed = restored
        #expect(JourneyEngine.completeCrossing(in: &restored) == nil && restored == completed)
    }

    @Test func crossingAllowsQueuedRestButNeverOrdinaryTravelDays() throws {
        var trip = Journey(seed: 42)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = OriginalRiverRules.dimensions(destination: 8, rain: 0)
        trip.riverDepth = 20; trip.riverWidth = 400
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        try JourneyEngine.beginRest(days: 1, in: &trip)
        try JourneyEngine.beginCrossing(.ferry, in: &trip)
        let outcome = trip.originalRiverOutcome
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.daysElapsed == 1 && trip.inventory[.food] == 985)
        #expect(trip.originalRiverOutcome == outcome && trip.phase == .river)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(!JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.daysElapsed == 2)
        JourneyEngine.prepareCrossingResult(in: &trip)
        JourneyEngine.completeCrossing(in: &trip)
        #expect(trip.phase == .landmark && trip.daysElapsed == 2)
    }
    @Test func lateCrossingDeathIsNotReportedTwiceAndFinishedCallbacksAreHarmless() throws {
        var trip = Journey(seed: 1)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = .init(depthHalfFeet: 40, widthTensFeet: 40)
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 12
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        var outcome = try #require(JourneyEngine.prepareCrossingResult(in: &trip))
        outcome.drownedMembers = [1]
        trip.originalRiverOutcome = outcome
        trip.members[1].health = 0
        JourneyEngine.completeCrossing(in: &trip)
        #expect(trip.phase == .landmark)
        #expect(!trip.journal.contains { $0.text.contains("wagon drowned") })
        trip.phase = .river; trip.originalRiverOutcome = outcome
        JourneyEngine.finish(&trip, won: false, reason: "The party died.")
        #expect(trip.originalRiverOutcome == nil)
        let finished = trip
        #expect(JourneyEngine.completeCrossing(in: &trip) == nil)
        #expect(trip == finished)
    }

    @Test func crossingHasNoDayFoodChargeAndOutcomeRoundTrips() throws {
        var trip = Journey(seed: 42)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = OriginalRiverRules.dimensions(destination: 8, rain: 0)
        trip.riverDepth = 20; trip.riverWidth = 400
        trip.inventory[.food] = 1000
        let originalCash = trip.cash
        try JourneyEngine.beginCrossing(.ferry, in: &trip)
        #expect(trip.cash == originalCash - 500 && trip.daysElapsed == 0 && trip.inventory[.food] == 1000)
        #expect(trip.phase == .river && trip.originalRiverOutcome?.status == 0)
        #expect(!trip.canCamp && trip.canSave)
        #expect(trip.randomState == 42) // zero risk at current5 means zero draws
        var restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(restored.originalRiverOutcome == trip.originalRiverOutcome)
        try JourneyStore().validate(restored)
        JourneyEngine.prepareCrossingResult(in: &restored)
        #expect(restored.randomState == 42)
        #expect(JourneyEngine.completeCrossing(in: &restored)?.status == 0)
        #expect(restored.phase == .landmark && restored.originalRiverOutcome == nil)
        let completed = restored
        #expect(JourneyEngine.completeCrossing(in: &restored) == nil)
        #expect(restored == completed)
    }

    private func restingRiver(seed: UInt32 = 42, food: Int = 1000) throws -> Journey {
        var trip = Journey(seed: seed)
        trip.phase = .river; trip.locationID = "green"; trip.destinationID = "green"
        trip.originalRiverDimensions = .init(depthHalfFeet: 40, widthTensFeet: 40)
        trip.riverDepth = 20; trip.riverWidth = 400
        trip.inventory[.food] = food; trip.inventory[.oxen] = 12
        try JourneyEngine.beginRest(days: 1, in: &trip)
        return trip
    }

    @Test(arguments: [10, 1000])
    func restDrawsBeforeLossesAndUsesLiveFood(food: Int) throws {
        var trip = try restingRiver(food: food)
        // Independent source sequence: ford at depth40 has no risk draw.
        // Run the real resting day first, then hand-compose CODE18's loss draws.
        var dayOracle = trip
        #expect(JourneyEngine.advanceActionDay(in: &dayOracle))
        #expect(dayOracle.randomState != 42)
        #expect(dayOracle.inventory[.food] == max(0, food - 15))
        var rng = OriginalRandom(seed: dayOracle.randomState)
        var losses = [12, 0, 0, 0, 0, 0, 0]
        if food > 15 {
            _ = rng.bounded(100) // Food threshold200: always selected.
            losses[6] = rng.bounded(food - 15 + 1)
        }
        for _ in 0..<6 { _ = rng.bounded(100) } // Six ox pairs, threshold190.
        for _ in 0..<5 { _ = rng.bounded(100) } // Four companions then leader.
        let delay = rng.bounded(180)

        try JourneyEngine.beginCrossing(.ford, in: &trip)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.randomState == dayOracle.randomState)
        let inventoryBeforeResult = trip.inventory
        let result = try #require(JourneyEngine.prepareCrossingResult(in: &trip))
        #expect(result.losses == losses)
        #expect(result.drownedMembers == [1, 2, 3, 4, 0])
        #expect(result.presentationRandomTicks == delay && trip.randomState == rng.seed)
        #expect(trip.inventory == inventoryBeforeResult && trip.livingMembers.count == 5)
        #expect(result.phase == .result)
    }

    @Test func caulkLossesUseResultTimeRainAndLivingSlots() {
        let risk = Draws([0])
        let choice = OriginalRiverRules.choose(method: .caulk, destination: 0,
            dimensions: depth(12), rain: 0, draw: risk.next)
        #expect(risk.sites == [0x042a] && choice.currentFactor == 3 && choice.status == 2)
        // Current rain3700 => factor40 => supply threshold12, not original3.
        // Dead companion1 is skipped; only live companion2 and then leader draw.
        let losses = Draws([10, 7, 0, 99, 17])
        let result = OriginalRiverRules.prepareResult(choice, destination: 0,
            dimensions: depth(12), rain: 3700, inventory: [0, 7, 0, 0, 0, 0, 0],
            living: [true, false, true], draw: losses.next)
        #expect(result.losses == [0, 7, 0, 0, 0, 0, 0])
        #expect(result.drownedMembers == [2] && result.currentFactor == 3)
        #expect(losses.sites == [0x1608, 0x1626, 0x1564, 0x15a4, 0x2296])
        #expect(result.presentationRandomTicks == 17)
    }

    @Test func resultRoundTripAndRepeatedPreparationNeverReroll() throws {
        var trip = try restingRiver()
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        let animation = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(animation.originalRiverOutcome?.phase == .animation)
        trip = animation
        let journal = trip.journal, cash = trip.cash
        JourneyEngine.prepareCrossingResult(in: &trip)
        trip = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        try JourneyStore().validate(trip)
        #expect(trip.originalRiverOutcome?.phase == .result)
        let prepared = trip
        #expect(JourneyEngine.prepareCrossingResult(in: &trip) == prepared.originalRiverOutcome)
        #expect(trip == prepared && trip.cash == cash && trip.journal == journal)
    }

    @Test func legacyPreparedOutcomeWithoutDelayNeverConsumesNewRandomness() throws {
        var trip = try restingRiver()
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        JourneyEngine.prepareCrossingResult(in: &trip)
        trip.originalRiverOutcome?.phase = nil
        trip.originalRiverOutcome?.presentationRandomTicks = nil
        trip = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        try JourneyStore().validate(trip)
        let legacy = trip
        #expect(trip.originalRiverOutcome?.isPrepared == true)
        JourneyEngine.prepareCrossingResult(in: &trip)
        #expect(trip == legacy)
        #expect(JourneyEngine.completeCrossing(in: &trip) == legacy.originalRiverOutcome)
    }

    @Test func newPhaseValidationRejectsPrematureLossesAndMissingFailureDelay() throws {
        var trip = try restingRiver()
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        try JourneyStore().validate(trip)
        var invalid = trip
        invalid.originalRiverOutcome?.losses[6] = 1
        #expect(throws: GameRuleError.self) { try JourneyStore().validate(invalid) }
        invalid = trip
        invalid.originalRiverOutcome?.drownedMembers = [1]
        #expect(throws: GameRuleError.self) { try JourneyStore().validate(invalid) }
        invalid = trip
        invalid.originalRiverOutcome?.presentationRandomTicks = 0
        #expect(throws: GameRuleError.self) { try JourneyStore().validate(invalid) }
        invalid = trip
        invalid.originalRiverOutcome?.phase = .result
        #expect(throws: GameRuleError.self) { try JourneyStore().validate(invalid) }
    }

    @Test func finishedJourneyIgnoresLateResultCreation() throws {
        var trip = try restingRiver()
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        JourneyEngine.finish(&trip, won: false, reason: "The party died while resting.")
        let finished = trip
        #expect(JourneyEngine.prepareCrossingResult(in: &trip) == nil)
        #expect(JourneyEngine.completeCrossing(in: &trip) == nil)
        #expect(trip == finished)
    }

    @Test @MainActor func controllerPersistsBothPhasesAndUsesSharedRestSeed() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        let game = GameController(store: store, random: OriginalRandomStream(seed: 42))
        game.trip = try restingRiver()
        game.crossRiver(.ford)
        #expect(game.error == nil)
        let animation = try store.load()
        #expect(animation.originalRiverOutcome?.phase == .animation && animation.randomState == 42)
        for _ in 0..<4 { game.tick() }
        #expect(game.trip?.daysElapsed == 1)
        var oracle = try #require(game.trip)
        JourneyEngine.prepareCrossingResult(in: &oracle)
        game.prepareCrossingResult()
        #expect(game.error == nil && game.trip == oracle)
        let savedResult = try store.load()
        #expect(savedResult == oracle && game.random.seed == oracle.randomState)
        game.prepareCrossingResult()
        #expect(game.trip == savedResult && game.random.seed == savedResult.randomState)
    }

    @Test func noInterveningDayKeepsOriginalLossDrawOrder() throws {
        var trip = try restingRiver(seed: 1)
        trip.inventory[.clothing] = 10
        var oracle = OriginalRandom(seed: 1)
        // Deep ford: clothing, food, six ox pairs, four companions, leader, delay.
        _ = oracle.bounded(100)
        let clothing = oracle.bounded(11)
        _ = oracle.bounded(100)
        let food = oracle.bounded(1001)
        for _ in 0..<11 { _ = oracle.bounded(100) }
        let delay = oracle.bounded(180)
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        let result = try #require(JourneyEngine.prepareCrossingResult(in: &trip))
        #expect(result.losses == [12, clothing, 0, 0, 0, 0, food])
        #expect(result.drownedMembers == [1, 2, 3, 4, 0])
        #expect(result.presentationRandomTicks == delay && trip.randomState == oracle.seed)
    }

    @Test(arguments: ["animation", "result", "legacy"])
    @MainActor func controllerResumeKeepsApplicationStreamAndPreparedLosses(stage: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        var saved = try restingRiver(seed: 1)
        try JourneyEngine.beginCrossing(.ford, in: &saved)
        if stage != "animation" { JourneyEngine.prepareCrossingResult(in: &saved) }
        if stage == "legacy" {
            saved.originalRiverOutcome?.phase = nil
            saved.originalRiverOutcome?.presentationRandomTicks = nil
        }
        try store.save(saved)
        let game = GameController(store: store, random: OriginalRandomStream(seed: 99))
        game.resume()
        #expect(game.error == nil && game.random.seed == 99)
        #expect(game.trip?.originalRiverOutcome == saved.originalRiverOutcome)
        #expect(game.trip?.cash == saved.cash && game.trip?.journal == saved.journal)
        #expect(game.trip?.randomState == 99) // Original load retains the process-global stream.
        game.prepareCrossingResult()
        #expect(game.error == nil)
        if stage == "animation" {
            var rng = OriginalRandom(seed: 99)
            _ = rng.bounded(100)
            let food = rng.bounded(1001)
            for _ in 0..<11 { _ = rng.bounded(100) }
            let delay = rng.bounded(180)
            #expect(game.trip?.originalRiverOutcome?.losses == [12, 0, 0, 0, 0, 0, food])
            #expect(game.trip?.originalRiverOutcome?.presentationRandomTicks == delay)
            #expect(game.random.seed == rng.seed)
            #expect(try store.load() == game.trip)
        } else {
            #expect(game.trip?.originalRiverOutcome == saved.originalRiverOutcome)
            #expect(game.random.seed == 99) // Prepared/legacy outcomes never reroll.
        }
    }

    @Test func caulkRiskPrecedesRestAndLossesFollowIt() throws {
        var trip = try restingRiver(seed: 1)
        // Green River factor5, first QuickDraw value16807: R100=7 <25 => tip.
        var dayOracle = trip
        dayOracle.randomState = 16807
        #expect(JourneyEngine.advanceActionDay(in: &dayOracle))
        try JourneyEngine.beginCrossing(.caulk, in: &trip)
        #expect(trip.originalRiverOutcome?.status == 2 && trip.randomState == 16807)
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.randomState == dayOracle.randomState)
        // Change the live displayed world before result creation, not the saved choice.
        trip.original?.weather.rain = 3700 // Green factor42, supply threshold13.
        trip.members[1].health = 0
        var rng = OriginalRandom(seed: dayOracle.randomState)
        let food = rng.bounded(100) < 13 ? rng.bounded(986) : 0
        var drowned: [Int] = []
        for member in [2, 3, 4] {
            if rng.bounded(100) < 45 { drowned.append(member) }
        }
        if drowned.count == 3 && rng.bounded(100) < 45 { drowned.append(0) }
        let delay = rng.bounded(180)
        let result = try #require(JourneyEngine.prepareCrossingResult(in: &trip))
        #expect(result.currentFactor == 5 && result.status == 2)
        #expect(result.losses == [0, 0, 0, 0, 0, 0, food])
        #expect(result.drownedMembers == drowned && !result.drownedMembers.contains(1))
        #expect(result.presentationRandomTicks == delay && trip.randomState == rng.seed)
    }

    @Test func rejectedCrossingIsAtomicAndRestPreservesArrivalDimensions() throws {
        var trip = Journey(seed: 42)
        trip.phase = .river; trip.locationID = "kansas"; trip.destinationID = "kansas"
        trip.originalRiverDimensions = OriginalRiverRules.dimensions(destination: 0, rain: 0)
        trip.riverDepth = 1; trip.riverWidth = 600
        let snapshot = trip
        #expect(throws: GameRuleError.self) { try JourneyEngine.cross(.ferry, in: &trip) }
        #expect(trip == snapshot)
        trip.inventory[.food] = 1000; trip.inventory[.clothing] = 10
        try JourneyEngine.rest(days: 1, in: &trip)
        #expect(trip.riverDepth == 1 && trip.riverWidth == 600)
    }
    @Test(arguments: [(2750,49,false), (2751,49,true), (2751,50,false)])
    func cdRiverIncludesBothFoodsAndUsesCachedOverloadBoundary(input: (Int,Int,Bool)) {
        let (weight, roll, loses) = input
        var sites: [Int] = []
        let result = OriginalRiverRules.resolve(method: .ford, destination: 0, dimensions: depth(6), rain: 0,
            inventory: [0,0,0,0,0,0,25,25], living: [true], edition: .macintoshCD12, wagonWeight: weight) { bound, site in
                sites.append(site)
                if site == 0x1608 { return roll }
                if site == 0x1626 { return 1 }
                return bound - 1
            }
        #expect(result.losses == [0,0,0,0,0,0,loses ? 1 : 0,loses ? 1 : 0])
        #expect(result.drownedMembers.isEmpty)
        #expect(sites == (loses ? [0x1608,0x1626,0x1608,0x1626,0x15a4,0x2296] : [0x1608,0x1608,0x15a4,0x2296]))
    }

    @Test func cdPaidChoiceLeavesEightInTheOriginalCurrentRegister() {
        let result = OriginalRiverRules.choose(method: .guide, destination: 11, dimensions: depth(12), rain: 92,
                                               edition: .macintoshCD12) { _, _ in 0 }
        #expect(result.currentFactor == 1 && result.status == 2 && result.losses.count == 8)
        let classic = OriginalRiverRules.choose(method: .guide, destination: 11, dimensions: depth(12), rain: 92) { _, _ in 0 }
        #expect(classic.currentFactor == 0 && classic.status == 0 && classic.losses.count == 7)
    }

    @Test func cdCrossingSaveReloadSettlesBothFoodLossesOnce() throws {
        var trip = try restingRiver(); trip.edition = .macintoshCD12
        trip.inventory.perishableFood = 100
        JourneyEngine.refreshWagonWeight(in: &trip)
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12)
        try store.save(trip)
        trip = try store.load()
        #expect(trip.originalRiverOutcome?.losses.count == 8)
        let result = try #require(JourneyEngine.prepareCrossingResult(in: &trip))
        #expect(result.losses.count == 8)
        try store.save(trip)
        var restored = try store.load()
        #expect(restored.originalRiverOutcome == result)
        let before = restored.inventory
        JourneyEngine.completeCrossing(in: &restored)
        #expect(restored.inventory[.food] == before[.food] - result.losses[6])
        #expect(restored.inventory.perishableFood == before.perishableFood - result.losses[7])
        let settled = restored
        #expect(JourneyEngine.completeCrossing(in: &restored) == nil && restored == settled)
    }

    @Test func cdSavedCrossingRejectsBadEighthLossAndMigratesLegacySeven() throws {
        var trip = try restingRiver(); trip.edition = .macintoshCD12
        try JourneyEngine.beginCrossing(.ford, in: &trip)
        trip.originalRiverOutcome?.phase = nil
        trip.originalRiverOutcome?.losses = [0,0,0,0,0,0,0,1001]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12)
        #expect(throws: GameRuleError.self) { try store.validate(trip) }
        trip.originalRiverOutcome?.losses = [0,0,0,0,0,0,10]
        let legacy = SavedJourney(format: "OregonBound", version: 2, journey: trip, edition: .macintoshCD12)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("legacy.json")
        try JSONEncoder().encode(legacy).write(to: url)
        var loaded = try store.load(from: url)
        #expect(loaded.originalRiverOutcome?.losses == [0,0,0,0,0,0,10,0])
        let seed = loaded.randomState
        JourneyEngine.prepareCrossingResult(in: &loaded)
        #expect(loaded.randomState == seed)
        JourneyEngine.completeCrossing(in: &loaded)
        #expect(loaded.inventory[.food] == 990 && loaded.inventory.perishableFood == 0)
    }

    @Test func cdLoadIsCachedAcrossMealsUntilNextPulseAndSurvivesSave() throws {
        var trip = try restingRiver(food: 2000); trip.edition = .macintoshCD12
        trip.inventory.perishableFood = 260
        #expect(JourneyEngine.advanceActionDay(in: &trip))
        #expect(trip.original?.cdWagonWeight == 2760)
        #expect(trip.inventory.cdWagonWeight == 2745)
        let restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(restored.original?.cdWagonWeight == 2760)
        JourneyEngine.refreshWagonWeight(in: &trip)
        #expect(trip.original?.cdWagonWeight == 2745)
    }

}
