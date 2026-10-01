import Foundation
import Testing
@testable import OregonBound

struct OriginalTradingRulesTests {
    private final class Draws {
        var values: [Int]
        var trace: [Int] = []
        var bounds: [Int] = []
        init(_ values: [Int]) { self.values = values }
        func next(_ bound: Int, _ site: Int) -> Int {
            trace.append(site)
            bounds.append(bound)
            let value = values.removeFirst()
            precondition((0..<bound).contains(value))
            return value
        }
    }
    private func wagon() -> Journey {
        var trip = Journey(seed: 42)
        trip.phase = .travel
        trip.inventory[.oxen] = 12
        trip.inventory[.food] = 1000
        return trip
    }

    @Test func cdSkipsPerishableAndRequestedCandidatesWithoutPriceDraws() throws {
        var trip = wagon(); trip.edition = .macintoshCD12
        let draws = Draws([334,7,3,8,20,15])
        let result = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip, draw: draws.next)
        #expect(result.offer == .init(item: 7, quantity: 1000))
        #expect(result.portrait == 22)
        #expect(draws.bounds == [1000,9,9,9,41,22])
        #expect(draws.trace == [0x451e,0x40fc,0x40fc,0x40fc,0x4220,0x48b0])
        #expect(result.edition == .macintoshCD12 && result.isValid)
    }

    @Test(arguments: 0..<22) func cdPortraitsUseIndividualSourceResources(_ roll: Int) throws {
        var trip = wagon(); trip.edition = .macintoshCD12
        let session = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip, draw: Draws([333,roll]).next)
        let expected = (roll == 15 ? 21 : roll == 17 ? 22 : roll) + 1
        #expect(session.portrait == expected && session.isValid)
        let art = session.artwork(in: trip.gameEdition)
        #expect(art.portraitResource == 16180 + expected && art.portraitFrame == 0)
        #expect(art.backgroundResource == 16180 && art.backgroundFrame == 0)
    }

    private func poorCDWagon() -> Journey {
        var trip = wagon(); trip.edition = .macintoshCD12; trip.cash = 0
        for supply in Supply.allCases { trip.inventory[supply] = 0 }
        return trip
    }
    private func failedCDTrade(_ trip: Journey, item: Int = 3, quantity: Int = 1) throws -> OriginalTradingRules.Session {
        let candidates = (0..<9).filter { $0 != 7 && $0 != (item == 7 ? 8 : item) }
        return try OriginalTradingRules.presentation(request: .init(item: item, quantity: quantity), trip: trip,
            draw: Draws([334] + candidates.flatMap { [$0,40] } + [0]).next)
    }

    @Test func cdFallbackRequiresLowHoldingsAndLimitedNoncashRequest() throws {
        var trip = poorCDWagon()
        #expect(try failedCDTrade(trip).offer == .init(item: 3, quantity: 1))
        trip.inventory.perishableFood = 100
        #expect(try failedCDTrade(trip).offer != nil)
        trip.inventory.perishableFood = 101
        #expect(try failedCDTrade(trip).offer == nil)
        trip.inventory.perishableFood = 0
        #expect(try failedCDTrade(trip, quantity: 2).offer == nil)
        #expect(try failedCDTrade(trip, item: 7, quantity: 100).offer == nil)
        for (item, limit) in [2,3,20,1,1,1,100].enumerated() {
            #expect(try failedCDTrade(trip, item: item, quantity: limit).offer == .init(item: item, quantity: limit))
            #expect(try failedCDTrade(trip, item: item, quantity: limit + 1).offer == nil)
        }
    }

    @Test func cdFallbackHoldingThresholdsUseDisplayedOxenAndWholeDollars() {
        let request = OriginalTradingRules.Request(item: 3, quantity: 1)
        for (item, threshold) in [11,5,20,1,1,1,100,100,100099].enumerated() {
            var trip = poorCDWagon()
            if item == 8 { trip.cash = threshold }
            else { trip.inventory[originalIndex: item] = threshold }
            #expect(OriginalTradingRules.permitsCDFallback(request, in: trip))
            if item == 8 { trip.cash += 1 }
            else { trip.inventory[originalIndex: item] += 1 }
            #expect(!OriginalTradingRules.permitsCDFallback(request, in: trip))
        }
    }

    @Test func cdSelfTradeUsesSourcePacketOverwriteAfterPaymentAndCapacityChecks() throws {
        for (item, amount, raw) in [(3,1,1),(0,2,4),(6,100,100)] {
            var trip = poorCDWagon(); trip.inventory[Supply.allCases[item]] = raw
            let session = OriginalTradingRules.Session(request: .init(item: item, quantity: amount),
                offer: .init(item: item, quantity: amount), portrait: 1, edition: .macintoshCD12)
            trip.originalTradeSession = session
            trip = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
            #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .accepted)
            #expect(trip.inventory[Supply.allCases[item]] == raw * 2)
            let completed = trip
            #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == nil && trip == completed)
            trip.originalTradeSession = session; trip.inventory[Supply.allCases[item]] = 0
            #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .cannotPay)
            trip.originalTradeSession = session; trip.inventory[Supply.allCases[item]] = OriginalTradingRules.capacities[item]
            #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .noSpace)
        }
    }

    @Test func cdPendingTradeRoundTripsThroughValidatedSaveStore() throws {
        var trip = poorCDWagon(); trip.phase = .landmark
        trip.originalTradeSession = try failedCDTrade(trip)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JourneyStore(directory: root, edition: .macintoshCD12)
        try store.save(trip)
        let loaded = try store.load()
        #expect(loaded.originalTradeSession == trip.originalTradeSession && loaded.randomState == trip.randomState)
        var wrong = trip; wrong.edition = .macintosh11
        #expect(throws: GameRuleError.self) { try JourneyStore(edition: .macintosh11).validate(wrong) }
        trip.originalTradeSession?.edition = .macintosh11
        #expect(throws: GameRuleError.self) { try store.validate(trip) }
    }

    @Test func cdSessionRejectsWrongEditionAndMalformedSelfTradesButKeepsLegacyOffer() throws {
        var trip = wagon()
        let session = OriginalTradingRules.Session(request: .init(item: 3, quantity: 1),
            offer: .init(item: 3, quantity: 1), portrait: 1, edition: .macintoshCD12)
        trip.originalTradeSession = session
        let before = trip
        #expect(throws: GameRuleError.self) { try OriginalTradingRules.finish(accept: true, in: &trip) }
        #expect(trip == before)
        var invalid = session; invalid.offer?.quantity = 2
        #expect(!invalid.isValid)
        invalid = session; invalid.portrait = 16
        #expect(!invalid.isValid)
        let legacy = try JSONDecoder().decode(OriginalTradingRules.Session.self,
            from: Data(#"{"request":{"item":3,"quantity":1},"offer":{"item":7,"quantity":1000},"portrait":0}"#.utf8))
        #expect(legacy.isValid && legacy.edition == nil)
        #expect(legacy.artwork(in: .macintoshCD12).portraitResource == nil)
        #expect(legacy.artwork(in: .macintoshCD12).backgroundResource == 16180)
        #expect(legacy.artwork(in: .macintosh11).portraitResource == 16080)
        trip.edition = .macintoshCD12; trip.originalTradeSession = legacy
        #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .accepted)
        #expect(trip.cash == 159000 && trip.inventory[.wheels] == 1)
    }

    @Test func quantityUsesStoredFloat32ThenTruncation() {
        #expect(OriginalTradingRules.paymentQuantity(request: .init(item: 3, quantity: 1), paymentItem: 6, percent: 90) == 44)
        #expect(OriginalTradingRules.paymentQuantity(request: .init(item: 1, quantity: 15), paymentItem: 3, percent: 90) == 13)
        #expect(OriginalTradingRules.paymentQuantity(request: .init(item: 3, quantity: 1), paymentItem: 0, percent: 80) == 1)
    }

    @Test func availabilityAndPortraitDrawOrder() throws {
        for roll in [333, 334] {
            let draws = Draws([roll] + (roll == 334 ? [3,7,20] : []) + [6,2])
            let result = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: wagon(), draw: draws.next)
            #expect((result.offer != nil) == (roll == 334))
            #expect(result.portrait == 2)
            #expect(draws.trace == [0x43d2] + (roll == 334 ? [0x3f7c,0x3f7c,0x4096] : []) + [0x4712,0x4712])
        }
    }

    @Test func cannotSpendLastWholeOxButCanRetryPaymentType() throws {
        var trip = wagon()
        trip.inventory[.oxen] = 3
        trip.inventory[.clothing] = 1
        let offer = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip,
            draw: Draws([334,0,20,1,20,0]).next).offer
        #expect(offer?.item == 1 && offer?.quantity == 1)
        trip.inventory[.food] = 50
        let retry = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip,
            draw: Draws([334,6,40,6,0,0]).next).offer
        #expect(retry?.item == 6 && retry?.quantity == 40)
    }

    @Test func allSevenFailedTypesProduceNoGift() throws {
        var trip = wagon(); trip.cash = 0
        for supply in Supply.allCases { trip.inventory[supply] = 0 }
        let draws = [334] + [0,1,2,4,5,6,7].flatMap { [$0,20] } + [1]
        let result = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip, draw: Draws(draws).next)
        #expect(result.offer == nil && result.portrait == 1)
    }

    @Test func requestValidationRejectsOverflowAndUsesRawCapacity() throws {
        var trip = wagon(); trip.inventory[.oxen] = 38
        #expect(try OriginalTradingRules.request(item: 0, displayedQuantity: 1, in: trip).quantity == 1)
        #expect(throws: GameRuleError.self) { try OriginalTradingRules.request(item: 0, displayedQuantity: 2, in: trip) }
        for item in [-1,0,7,8] {
            #expect(throws: GameRuleError.self) { try OriginalTradingRules.request(item: item, displayedQuantity: Int.max, in: trip) }
        }
    }

    @Test func sessionPersistsAndAcceptInstallsOnlyInventoryOnce() throws {
        var trip = wagon(); trip.markBroken(.wheels)
        let days = trip.daysElapsed, food = trip.inventory[.food], seed = trip.randomState
        trip.originalTradeSession = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip,
            draw: Draws([334,7,20,0]).next)
        trip = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(trip))
        #expect(trip.originalTradeSession?.isValid == true)
        let result = try OriginalTradingRules.finish(accept: true, in: &trip)
        #expect(result == .accepted && trip.cash == 159000 && trip.inventory[.wheels] == 1)
        #expect(trip.damagedParts == [.wheels] && trip.daysElapsed == days && trip.inventory[.food] == food)
        #expect(trip.randomState == seed && trip.originalTradeSession == nil)
        let completed = trip
        #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == nil)
        #expect(trip == completed)
    }

    @Test func refusalAndRevalidationAreAtomic() throws {
        var trip = wagon()
        let session = try OriginalTradingRules.presentation(request: .init(item: 3, quantity: 1), trip: trip, draw: Draws([334,7,20,0]).next)
        trip.originalTradeSession = session
        let inventory = trip.inventory, cash = trip.cash
        #expect(try OriginalTradingRules.finish(accept: false, in: &trip) == .refused)
        #expect(trip.inventory == inventory && trip.cash == cash && trip.journal.isEmpty)
        trip.originalTradeSession = session; trip.inventory[.wheels] = 3; trip.cash = 0
        #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .noSpace)
        #expect(trip.inventory[.wheels] == 3 && trip.cash == 0)
    }

    @Test func cashRequestsAndOxenPaymentsConvertUnitsExactly() throws {
        var trip = wagon(); trip.inventory[.oxen] = 6; trip.cash = 0
        trip.originalTradeSession = try OriginalTradingRules.presentation(
            request: OriginalTradingRules.request(item: 7, displayedQuantity: 40, in: trip), trip: trip,
            draw: Draws([334,0,20,0]).next)
        #expect(trip.originalTradeSession?.offer?.quantity == 2)
        #expect(try OriginalTradingRules.finish(accept: true, in: &trip) == .accepted)
        #expect(trip.cash == 4000 && trip.inventory[.oxen] == 2)
    }

    @Test func malformedSessionCannotIndexInventoryOrOverflow() throws {
        var trip = wagon()
        for item in [-1,8,Int.max] {
            let session = OriginalTradingRules.Session(request: .init(item: item, quantity: Int.max), offer: nil, portrait: 0)
            #expect(!session.isValid)
            trip.originalTradeSession = session
            #expect(throws: GameRuleError.self) { try OriginalTradingRules.finish(accept: true, in: &trip) }
        }
    }

    @Test func realSeedContinuationAndRequestRejectionPreserveDraws() throws {
        var a = wagon()
        var b = a
        try OriginalTradingRules.begin(item: 3, displayedQuantity: 1, in: &a)
        try OriginalTradingRules.begin(item: 3, displayedQuantity: 1, in: &b)
        #expect(a == b)
        let pending = a
        #expect(throws: GameRuleError.self) { try OriginalTradingRules.begin(item: 3, displayedQuantity: 1, in: &a) }
        #expect(a == pending)
        var invalid = wagon(); let before = invalid
        #expect(throws: GameRuleError.self) { try OriginalTradingRules.begin(item: 3, displayedQuantity: 0, in: &invalid) }
        #expect(invalid == before)
    }
}
