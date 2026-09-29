import Foundation
import Testing
@testable import OregonBound

struct OriginalTradingRulesTests {
    private final class Draws {
        var values: [Int]
        var trace: [Int] = []
        init(_ values: [Int]) { self.values = values }
        func next(_ bound: Int, _ site: Int) -> Int {
            trace.append(site)
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
