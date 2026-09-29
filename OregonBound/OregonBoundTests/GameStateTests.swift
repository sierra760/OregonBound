import XCTest
@testable import OregonBound

final class GameStateTests: XCTestCase {

    // (a) JSON round-trip preserves all fields across a populated state with 2 players.
    func testJSONRoundTrip() throws {
        var p1 = PlayerState()
        p1.statusFlags = 0x20
        p1.supply = [100, 50, 200, 10, 5, 30, 20]
        p1.cashInt = 1000
        p1.extraResource = 5
        p1.illnessRate = 3
        p1.sickDaysLeft = 10
        p1.diseaseType = 2
        p1.diseaseDuration = 7
        p1.technologyLevel = 1
        p1.restDays = 0
        p1.scoreField = 42

        var p2 = PlayerState()
        p2.supply = [80, 10, 150, 8, 2, 15, 0]
        p2.diseaseType = 0xFF

        var state = GameState()
        state.startingYear = 1848
        state.professionClass = 3
        state.gameStateFlags = 0x02
        state.eventCountdown = 5
        state.animalCountdown = 3
        state.activePartyCount = 2
        state.currentPlayerIdx = 0
        state.playerSlots = [0, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        state.seasonMonth = 4
        state.weatherDirection = 3
        state.weatherSeverity = 1
        state.distanceToNext = 350
        state.milesTraveled = 250
        state.windSpeedEast = 20
        state.windSpeedWest = 0
        state.trailMonth = 4
        state.origPartySize = 2
        state.maxPartySlots = 32
        state.targetLocationId = 7
        state.targetLocationPos = 1200
        state.players = [p1, p2]

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GameState.self, from: data)

        XCTAssertEqual(state, decoded)
    }

    // (b) GameState has at least 21 stored properties.
    func testGameStateFieldCount() {
        let mirror = Mirror(reflecting: GameState())
        XCTAssertGreaterThanOrEqual(mirror.children.count, 21,
            "GameState must expose at least 21 stored properties via Mirror")
    }

    // (c) PlayerState has at least 11 stored properties.
    func testPlayerStateFieldCount() {
        let mirror = Mirror(reflecting: PlayerState())
        XCTAssertGreaterThanOrEqual(mirror.children.count, 11,
            "PlayerState must expose at least 11 stored properties via Mirror")
    }

    // (d) Default GameState has an empty players array.
    func testDefaultPlayersEmpty() {
        let state = GameState()
        XCTAssertTrue(state.players.isEmpty)
    }

    // (e) Supply array is always length 7.
    func testSupplyArrayLength() {
        let p = PlayerState()
        XCTAssertEqual(p.supply.count, 7)
    }
}
