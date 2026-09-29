import XCTest
@testable import OregonBound

final class ContinuityTests: XCTestCase {
    @MainActor func testLandmarkMapToggleAndOtherPaneReplacement() {
        let controller = GameController(random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41)
        trip.locationID = "kearney"; trip.phase = .landmark
        controller.trip = trip
        controller.open(.map)
        XCTAssertTrue(controller.showingTravelMap)
        XCTAssertNil(controller.panel)
        controller.open(.map)
        XCTAssertFalse(controller.showingTravelMap)
        controller.open(.guide)
        controller.open(.map)
        XCTAssertFalse(controller.showingTravelMap)
        XCTAssertNil(controller.panel)
        trip.originalMapSuppressedLandmarkID = "kearney"
        controller.trip = trip
        controller.open(.map)
        XCTAssertTrue(controller.showingTravelMap)
        controller.open(.map)
        XCTAssertTrue(controller.showingTravelMap)
    }

    @MainActor func testEngineActionsKeepInterleavedSceneRandomDraws() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let random = OriginalRandomStream(seed: 41)
        let controller = GameController(store: JourneyStore(directory: folder), random: random)
        controller.trip = Journey(seed: 999)
        var expected = OriginalRandom(seed: 41)
        XCTAssertEqual(random.bounded(100), expected.bounded(100))
        controller.perform { trip in
            var engineRandom = OriginalRandom(seed: trip.randomState)
            XCTAssertEqual(engineRandom.bounded(50), expected.bounded(50))
            trip.randomState = engineRandom.seed
        }
        XCTAssertEqual(random.bounded(9), expected.bounded(9))
        controller.perform { trip in XCTAssertEqual(trip.randomState, expected.seed) }
        XCTAssertEqual(controller.trip?.randomState, expected.seed)
    }

    @MainActor func testDeathPresentationPreservesPendingRestAndStopsMovement() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41)
        trip.phase = .travel; trip.original?.flags = 6; trip.original?.restDays = 2
        controller.trip = trip
        controller.perform { $0.members[1].health = 0 }
        XCTAssertNotNil(controller.memorialID)
        XCTAssertEqual(controller.trip?.original?.flags, 4)
        XCTAssertEqual(controller.trip?.original?.restDays, 2)
        XCTAssertFalse(controller.running)
    }

    @MainActor func testOriginalUITimerRestAndTimeOutUseSeparateFlags() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41)
        try JourneyEngine.completeOutfitting([.oxen: 6, .food: 1000], in: &trip)
        try JourneyEngine.chooseDeparture(month: 4, in: &trip)
        controller.trip = trip
        controller.continueJourney()
        XCTAssertTrue(controller.running)
        controller.open(.rest)
        XCTAssertTrue(controller.running, "Opening the rest pane preserves the original moving bit")
        controller.perform { try JourneyEngine.beginRest(days: 1, in: &$0) }
        controller.panel = nil
        for _ in 0..<3 { controller.tick() }
        XCTAssertEqual(controller.trip?.daysElapsed, 0)
        controller.tick()
        XCTAssertEqual(controller.trip?.daysElapsed, 1)
        XCTAssertEqual(controller.trip?.miles, 0)
        controller.continueJourney() // Time Out clears movement, but does not cancel rest.
        XCTAssertFalse(controller.running)
        for _ in 0..<4 { controller.tick() }
        XCTAssertEqual(controller.trip?.daysElapsed, 2)
        XCTAssertEqual(controller.trip?.miles, 0)
        XCTAssertEqual((controller.trip?.original?.flags ?? 255) & 6, 0)
        for _ in 0..<8 { controller.tick() }
        XCTAssertEqual(controller.trip?.daysElapsed, 2)
        XCTAssertNil(controller.error)
    }

    @MainActor func testBackgroundSuspendsTimerWithoutChangingOriginalAction() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = GameController(store: JourneyStore(directory: folder), random: OriginalRandomStream(seed: 41))
        var trip = Journey(seed: 41)
        try JourneyEngine.completeOutfitting([.oxen: 6, .food: 1000], in: &trip)
        try JourneyEngine.chooseDeparture(month: 4, in: &trip)
        controller.trip = trip
        controller.continueJourney()
        controller.applicationActive = false
        for _ in 0..<8 { controller.tick() }
        XCTAssertEqual(controller.trip?.daysElapsed, 0)
        XCTAssertTrue(controller.running)
        controller.applicationActive = true
        for _ in 0..<4 { controller.tick() }
        XCTAssertEqual(controller.trip?.daysElapsed, 1)
        XCTAssertGreaterThan(controller.trip?.miles ?? 0, 0)
    }

    @MainActor func testUnreadableHallOfFameDoesNotLoseCompletedJourney() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        var trip = Journey(seed: 1)
        trip.phase = .fork
        trip.locationID = "dalles"
        trip.inventory[.food] = 100
        try store.save(trip)
        try Data("broken scoreboard".utf8).write(to: folder.appendingPathComponent("hall-of-fame.json"))
        let controller = GameController(store: store, random: OriginalRandomStream(seed: 1))
        controller.resume()
        controller.perform { JourneyEngine.finish(&$0, won: true, reason: "Arrived") }
        controller.submitOriginalScore(name: "Test")
        XCTAssertEqual(try store.load().phase, .finished)
        XCTAssertNotNil(controller.error)
    }

    @MainActor func testResumingVictoryWaitsForNameAndRecordsScoreOnlyOnce() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        var trip = Journey(seed: 1)
        JourneyEngine.finish(&trip, won: true, reason: "Arrived")
        try store.save(trip)
        let controller = GameController(store: store, random: OriginalRandomStream(seed: 1))
        controller.resume()
        XCTAssertEqual(try store.scores().count, 0)
        controller.submitOriginalScore(name: "Test")
        controller.resume()
        controller.submitOriginalScore(name: "Test")
        XCTAssertEqual(try store.scores().count, 1)
    }

    func testSaveLoadAndMalformedSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        let trip = Journey(seed: 123)
        try store.save(trip)
        XCTAssertEqual(try store.load(), trip)
        try Data("not a saved game".utf8).write(to: store.saveURL)
        XCTAssertThrowsError(try store.load())
    }

    func testInvalidGameIsRejectedBeforeReplacingGoodSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        let original = Journey(seed: 4)
        try store.save(original)
        var invalid = original
        invalid.locationID = "does-not-exist"
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try store.load(), original)
        invalid = original
        invalid.members = []
        XCTAssertThrowsError(try store.save(invalid))
    }

    func testHallOfFameDeduplicatesAndKeepsTenHighestScores() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JourneyStore(directory: folder)
        for n in 0..<15 {
            var trip = Journey(seed: UInt32(n))
            trip.cash = n * 1000
            JourneyEngine.finish(&trip, won: true, reason: "Arrived")
            try store.recordScore(trip)
            try store.recordScore(trip)
        }
        let scores = try store.scores()
        XCTAssertEqual(scores.count, 10)
        XCTAssertEqual(Set(scores.map(\.id)).count, 10)
        XCTAssertEqual(scores.map(\.score), scores.map(\.score).sorted(by: >))
    }

    func testHuntCountsAmmunitionAndDoesNotRewardMisses() {
        var hunt = HuntSession(ammunition: 2, duration: 30, seed: 42)
        XCTAssertFalse(hunt.shoot(x: -100, y: -100))
        XCTAssertEqual(hunt.shots, 1)
        XCTAssertEqual(hunt.food, 0)
        _ = hunt.shoot(x: -100, y: -100)
        _ = hunt.shoot(x: -100, y: -100)
        XCTAssertEqual(hunt.shots, 2)
        XCTAssertTrue(hunt.finished)
    }

    func testHuntHitAwardsAnimalOnceAndTimerExpires() throws {
        var hunt = HuntSession(ammunition: 10, duration: 30, seed: 42)
        hunt.advance(seconds: 1)
        let animal = try XCTUnwrap(hunt.animals.first)
        XCTAssertTrue(hunt.shoot(x: animal.x, y: animal.y))
        let food = hunt.food
        XCTAssertGreaterThan(food, 0)
        _ = hunt.shoot(x: animal.x, y: animal.y)
        XCTAssertEqual(hunt.food, food)
        hunt.advance(seconds: 31)
        XCTAssertTrue(hunt.finished)
    }

    func testRaftCanReachLandingAndSteeringStaysInRiver() {
        var raft = RaftSession(seed: 12)
        raft.steer(to: -10)
        XCTAssertEqual(raft.position, 0.08)
        raft.steer(to: 10)
        XCTAssertEqual(raft.position, 0.92)
        for _ in 0..<6000 where !raft.finished {
            raft.steer(to: 0.08)
            raft.advance(seconds: 0.02)
        }
        XCTAssertTrue(raft.finished)
        XCTAssertTrue(raft.landed)
    }
}
