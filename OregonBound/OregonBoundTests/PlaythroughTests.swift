import XCTest
@testable import OregonBound

final class PlaythroughTests: XCTestCase {
    func testCompleteJourneysBothBranchesAndEndings() throws {
        for longRoute in [false, true] {
            for raftEnding in [false, true] {
                var trip = try JourneyTests().outfitted(seed: 73)
                for _ in 0..<1500 where trip.phase != .finished {
                    if trip.canShop && trip.inventory[.food] < 600 && trip.cash > JourneyEngine.price(.food, quantity: 500, in: trip) {
                        try JourneyEngine.buy(.food, quantity: 500, in: &trip)
                    }
                    if trip.canCamp && trip.inventory[.oxen] == 0 {
                        try requestTrade(.oxen, in: &trip)
                    }
                    if trip.canCamp && trip.brokenPart != nil {
                        for part in trip.damagedParts where trip.inventory[part] == 0 {
                            try requestTrade(part, in: &trip)
                        }
                        try JourneyEngine.repair(&trip)
                        continue
                    }
                    if trip.canHunt && trip.inventory[.food] < 200 {
                        try JourneyEngine.beginHunt(&trip)
                        guard trip.phase == .hunting else { break }
                        var random = OriginalRandom(seed: trip.randomState)
                        let input = OriginalHuntSession.Input(
                            destination: (TrailCatalog.stops.firstIndex { $0.id == (trip.destinationID ?? trip.locationID) } ?? 1) - 1,
                            month: trip.month, weatherCategory: trip.originalWeatherCategory,
                            snow: (trip.original?.weather.snow ?? 0) != 0, mileage: trip.miles,
                            lastSuccessfulHuntMileage: trip.original?.lastSuccessfulHuntMileage ?? 0,
                            ammunition: trip.inventory[.bullets], survivors: trip.livingMembers.count,
                            currentFood: trip.inventory[.food], foodCapacity: Supply.food.capacity,
                            timeSetting: 3, originalDisplayFlag: true)
                        var hunt = OriginalHuntSession(input: input, startTick: 0) { random.bounded($0) }
                        for tick in stride(from: 0, through: 3000, by: 3) where !hunt.isComplete {
                            hunt.advance(to: tick) { random.bounded($0) }
                            if hunt.foodShot >= 200 { hunt.stop() }
                            if hunt.projectile == nil, let animal = hunt.objects.first(where: {
                                if case .animal = $0.role { return !$0.deleted && $0.visible && $0.velocity != 0 && $0.rect.x > 80 && $0.rect.right < 430 }
                                return false
                            }) {
                                let y = animal.rect.y + animal.rect.height / 2
                                var x = animal.rect.x + animal.rect.width / 2
                                for _ in 0..<3 {
                                    let flight = max(abs(x - 256), abs(y - 228)) / 20
                                    x = animal.rect.x + animal.rect.width / 2 + animal.velocity * (flight + 1)
                                }
                                _ = hunt.shoot(x: x, y: y)
                            }
                        }
                        let result = try XCTUnwrap(hunt.result)
                        trip.randomState = random.seed
                        try JourneyEngine.finishHunt(result: result, in: &trip)
                        continue
                    }
                    // Original Fair health can be a stable cold-weather state;
                    // resting whenever a compatibility percentage is below75
                    // creates a permanent rest/travel cycle. Rest at Poor instead.
                    if trip.canCamp && trip.healthBadness >= 70 && trip.inventory[.food] > 80 { try JourneyEngine.rest(days: 2, in: &trip) }
                    switch trip.phase {
                    case .travel: JourneyEngine.advanceDay(&trip)
                    case .landmark, .outfitting: try JourneyEngine.depart(&trip)
                    case .departure: try JourneyEngine.chooseDeparture(month: 4, in: &trip)
                    case .river:
                        let available = JourneyEngine.availableCrossings(in: trip)
                        let method: CrossingMethod = trip.riverDepth < 2.5 ? .ford
                            : available.contains(.ferry) && trip.cash >= 500 ? .ferry
                            : available.contains(.guide) && trip.inventory[.clothing] >= 3 ? .guide : .caulk
                        try JourneyEngine.cross(method, in: &trip)
                    case .fork:
                        if trip.locationID == "dalles" {
                            if raftEnding { try JourneyEngine.beginRaft(&trip) }
                            else { try JourneyEngine.takeBarlowRoad(&trip) }
                        } else {
                            let route = longRoute ? trip.location.routes.first! : trip.location.routes.last!
                            try JourneyEngine.chooseRoute(route.destination, in: &trip)
                        }
                    case .rafting:
                        try completeRaft(&trip)
                    case .hunting: XCTFail("Hunting should settle in its own action")
                    case .finished: break
                    }
                    try JourneyStore().validate(trip)
                }
                XCTAssertEqual(trip.phase, .finished)
                XCTAssertTrue(trip.won, "route=\(longRoute), raft=\(raftEnding): \(trip.finishReason), days=\(trip.daysElapsed)")
                XCTAssertEqual(trip.locationID, "oregon")
                XCTAssertGreaterThan(JourneyEngine.score(trip), 0)
                XCTAssertTrue(trip.visited.contains("bridger") == longRoute)
                XCTAssertTrue(trip.visited.contains("walla") == longRoute)
            }
        }
    }

    func testCorruptJournalSequenceCannotOverflowOnResume() throws {
        var trip = Journey(seed: 1)
        trip.journal = [JournalEntry(id: Int.max, day: 0, text: "Corrupt")]
        XCTAssertThrowsError(try JourneyStore().validate(trip))
        trip.journal = [JournalEntry(id: 0, day: Int.max, text: "Corrupt")]
        XCTAssertThrowsError(try JourneyStore().validate(trip))
    }

    func testSaveRejectsImpossibleForkAndTravelRoute() throws {
        var trip = Journey(seed: 1)
        trip.phase = .fork
        trip.locationID = "oregon"
        XCTAssertThrowsError(try JourneyStore().validate(trip))
        trip.phase = .travel
        trip.locationID = "independence"
        trip.destinationID = "oregon"
        XCTAssertThrowsError(try JourneyStore().validate(trip))
    }

    func testRaftingDoesNotInventDaysOrConsumeFoodAtTheFirstAnniversary() throws {
        var trip = try JourneyTests().outfitted()
        trip.locationID = "dalles"
        trip.phase = .fork
        trip.daysElapsed = 364
        try JourneyEngine.beginRaft(&trip)
        let food = trip.inventory[.food]
        try completeRaft(&trip)
        XCTAssertEqual(trip.inventory[.food], food)
        XCTAssertEqual(trip.daysElapsed, 364)
        XCTAssertTrue(trip.won)
        XCTAssertNoThrow(try JourneyStore().validate(trip))
    }
    private func requestTrade(_ item: Supply, in trip: inout Journey) throws {
        let index = try XCTUnwrap(Supply.allCases.firstIndex(of: item))
        for _ in 0..<100 where trip.inventory[item] == 0 {
            try OriginalTradingRules.begin(item: index, displayedQuantity: 1, in: &trip)
            _ = try OriginalTradingRules.finish(accept: true, in: &trip)
        }
        XCTAssertGreaterThan(trip.inventory[item], 0)
    }

    private func completeRaft(_ trip: inout Journey) throws {
        var random = OriginalRandom(seed: trip.randomState)
        var raft = OriginalRaftSession(input: JourneyEngine.originalRaftInput(trip), startTick: 0) { random.bounded($0) }
        for tick in stride(from: 0, through: 15000, by: 3) where !raft.isComplete {
            // Look ahead using the visible rock trajectories, without peeking at RNG.
            // Choose the nearest reachable gap that stays clear of every visible rock.
            let targets = Array(stride(from: 10, through: 350, by: 20)) + [raft.raftLeft]
            let target = targets.min { predictedRisk($0, raft: raft) < predictedRisk($1, raft: raft) }!
            let mouseX = target < raft.raftLeft ? target : target > raft.raftLeft ? target + 63 : target + 31
            raft.advance(to: tick, mouseX: mouseX) { random.bounded($0) }
        }
        let result = try XCTUnwrap(raft.result)
        try JourneyEngine.finishRaft(result: result, randomSeed: random.seed, in: &trip)
    }

    private func predictedRisk(_ target: Int, raft: OriginalRaftSession) -> Int {
        var x = raft.raftLeft
        var rocks = raft.rocks
        var collisions = 0
        for _ in 0..<110 {
            let direction = target > x ? 1 : target < x ? -1 : 0
            for i in rocks.indices {
                if OriginalRaftSession.hits(rockX: rocks[i].x, rockY: rocks[i].y, raftLeft: x, direction: direction) { collisions += 1 }
                rocks[i].accumulator = Float(Double(rocks[i].accumulator) + Double(rocks[i].slope) * 2)
                if rocks[i].slope < 0 && rocks[i].accumulator < -2 { rocks[i].x -= 2; rocks[i].accumulator += 2 }
                if rocks[i].slope > 0 && rocks[i].accumulator > 2 { rocks[i].x += 2; rocks[i].accumulator -= 2 }
                rocks[i].y += 2
            }
            x = min(350, max(10, x + direction * min(4, abs(target - x))))
        }
        return collisions * 10000 + abs(target - raft.raftLeft)
    }

}
