import Foundation
import Testing
@testable import OregonBound

struct OriginalStoreRulesTests {
    private func fort(_ id: String = "kearney") -> Journey {
        var trip = Journey(seed: 42); trip.phase = .landmark; trip.locationID = id
        trip.inventory[.oxen] = 3; trip.inventory[.bullets] = 39
        return trip
    }
    @Test func cdStoreSellsOnlyStoredFoodAndPreservesIndependentFreshCapacity() throws {
        var trip = fort(); trip.edition = .macintoshCD12
        trip.inventory[.food] = 1900; trip.inventory.perishableFood = 1000
        #expect(OriginalStoreRules.have(in: trip).count == 7)
        #expect(OriginalStoreRules.have(in: trip)[6] == 1900)
        let purchase = try OriginalStoreRules.buy([0,0,0,0,0,0,100], in: &trip)
        #expect(purchase.total == 2500 && trip.inventory[.food] == 2000)
        #expect(trip.inventory.perishableFood == 1000)
        let before = trip
        #expect(throws: OriginalStoreRules.Rejection.self) {
            try OriginalStoreRules.buy([0,0,0,0,0,0,1], in: &trip)
        }
        #expect(throws: OriginalStoreRules.Rejection.self) {
            try OriginalStoreRules.buy([0,0,0,0,0,0,0,1], in: &trip)
        }
        #expect(trip == before)
    }

    @Test func eligibilityMatchesOriginalStoppedDestinationSet() {
        let stores = Set(["independence","kearney","laramie","bridger","hall","boise","walla"])
        for stop in TrailCatalog.stops { #expect(OriginalStoreRules.isAvailable(in: fort(stop.id)) == stores.contains(stop.id)) }
        var moving = fort(); moving.phase = .travel; moving.legProgress = moving.legDistance
        #expect(!OriginalStoreRules.isAvailable(in: moving))
    }
    @Test func boxAndOxenUnitsAndHaveColumnMatchOriginal() {
        #expect(OriginalStoreRules.have(in: fort()) == [2,0,1,0,0,0,0])
        #expect(OriginalStoreRules.rawQuantity(item: 0, count: 1) == 2)
        #expect(OriginalStoreRules.rawQuantity(item: 2, count: 1) == 20)
        #expect(OriginalStoreRules.rawQuantity(item: 6, count: 1) == 1)
    }
    @Test func pricesUseRegionalPercentageAndMatchEngineForValidUnits() throws {
        for id in ["independence","kearney","laramie","bridger","hall","boise","walla"] {
            let trip = fort(id)
            for (i, supply) in Supply.allCases.enumerated() {
                let quantity = i == 2 ? 20 : 1
                #expect(OriginalStoreRules.rowCost(item: i, count: 1, in: trip) == JourneyEngine.price(supply, quantity: quantity, in: trip))
            }
        }
        #expect(OriginalStoreRules.rowCost(item: 2, count: 1, in: fort()) == 250)
        #expect(OriginalStoreRules.rowCost(item: 6, count: 1, in: fort("bridger")) == 35)
    }
    @Test func cartIsAtomicAndPreservesDayRandomDamage() throws {
        var trip = fort(); trip.markBroken(.wheels)
        let days = trip.daysElapsed, seed = trip.randomState, cash = trip.cash
        let result = try OriginalStoreRules.buy([1,1,2,1,0,0,100], in: &trip)
        #expect(result.total == 8000)
        #expect(trip.cash == cash - 8000 && trip.inventory[.oxen] == 5 && trip.inventory[.bullets] == 79)
        #expect(trip.inventory[.wheels] == 1 && trip.damagedParts == [.wheels])
        #expect(trip.daysElapsed == days && trip.randomState == seed && trip.journal.count == 1)
    }
    @Test func paymentFailurePrecedesCapacityOnSameRowButCartRemainsAtomic() {
        var trip = fort(); trip.cash = 1; trip.inventory[.oxen] = 40
        let before = trip
        do { _ = try OriginalStoreRules.buy([1,0,0,0,0,0,0], in: &trip); Issue.record("Expected rejection") }
        catch let error as OriginalStoreRules.Rejection { #expect(error == .insufficientMoney) }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(trip == before)
    }
    @Test func laterInvalidRowDoesNotApplyEarlierRows() {
        var trip = fort(); trip.inventory[.wheels] = 3
        let before = trip
        do { _ = try OriginalStoreRules.buy([1,0,0,1,0,0,0], in: &trip); Issue.record("Expected rejection") }
        catch let error as OriginalStoreRules.Rejection { #expect(error == .capacity(item: 3, quantity: 1)) }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(trip == before)
    }
    @Test func bulletCapacityCountsLooseBulletsAndErrorUsesRawQuantity() {
        var trip = fort(); trip.inventory[.bullets] = 1970
        do { _ = try OriginalStoreRules.buy([0,0,1,0,0,0,0], in: &trip); Issue.record("Expected rejection") }
        catch let error as OriginalStoreRules.Rejection { #expect(error == .capacity(item: 2, quantity: 20)) }
        catch { Issue.record("Unexpected error: \(error)") }
    }
    @Test func originalMoneyAndCapacityMessageUseGrouping() {
        #expect(OriginalStoreRules.money(160000) == "1,600.00")
        #expect(OriginalStoreRules.money(250) == "2.50")
        #expect(OriginalStoreRules.Rejection.capacity(item: 6, quantity: 3000).errorDescription?.contains("3,000 more pounds of food") == true)
    }
    @Test func emptyCartAndMalformedInputHaveNoEffects() throws {
        var trip = fort(); let before = trip
        #expect(try OriginalStoreRules.buy(Array(repeating: 0, count: 7), in: &trip).total == 0)
        #expect(trip == before)
        for cart in [[Int.max,0,0,0,0,0,0], [-1,0,0,0,0,0,0], []] {
            #expect(throws: OriginalStoreRules.Rejection.self) { try OriginalStoreRules.buy(cart, in: &trip) }
            #expect(trip == before)
        }
    }
}
