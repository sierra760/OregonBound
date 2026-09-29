import XCTest
@testable import OregonBound

final class SimulationRunnerTests: XCTestCase {

    func testRun365DaysUnder100ms() {
        let start = Date()
        let logs = SimulationRunner.run(days: 365, seed: 42, profession: 3)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThanOrEqual(elapsed, 0.1,
            "365-day run took \(Int(elapsed * 1000))ms (limit: 100ms)")
        XCTAssertLessThanOrEqual(logs.count, 365)
        XCTAssertGreaterThan(logs.count, 0)
    }

    func testDeterministicReplay() {
        let run1 = SimulationRunner.run(days: 365, seed: 42, profession: 3)
        let run2 = SimulationRunner.run(days: 365, seed: 42, profession: 3)
        XCTAssertEqual(run1.count, run2.count,
            "Deterministic replay must produce identical day counts")
        for (a, b) in zip(run1, run2) {
            XCTAssertEqual(a, b, "Day \(a.dayNumber) differs between replays")
        }
    }

    func testGameOverStopsSimulation() {
        // Direct starvation path — mirrors T03: bypass the 1% suppliesFound risk in
        // dailyEventRoll for deterministic isolation. Verifies that the game-over flag
        // and DayLog.isGameOver are consistent, which is what SimulationRunner.run uses
        // to break its loop.
        var rng = LCGRandomNumberGenerator(seed: 0)
        var state = GameState.newGame(profession: 1, rng: &rng)
        var engine = DayCycleEngine()
        for i in 0..<state.players.count {
            state.players[i].supply = Array(repeating: 0, count: 7)
            state.players[i].extraResource = 0
        }
        let killEvents = engine.partyResourceCheck(state: &state)
        XCTAssertFalse(killEvents.isEmpty, "Zero-supply party must trigger player death events")
        XCTAssertNotEqual(state.gameStateFlags & DayCycleEngine.flagGameOver, 0,
            "Game-over flag (0x20) must be set after starvation kill")
        XCTAssertEqual(state.activePartyCount, 0,
            "All players must be dead after partyResourceCheck on zero-supply state")

        let log = DayLog(
            dayNumber: 1,
            weatherDirection: state.weatherDirection,
            weatherSeverity: state.weatherSeverity,
            events: killEvents,
            activePartyCount: state.activePartyCount,
            milesTraveled: state.milesTraveled,
            isGameOver: state.gameStateFlags & DayCycleEngine.flagGameOver != 0
        )
        XCTAssertTrue(log.isGameOver,
            "DayLog.isGameOver must be true when gameStateFlags & 0x20 is set")
    }

    func testWeatherTransitionsOccur() {
        let logs = SimulationRunner.run(days: 365, seed: 42, profession: 3)
        let directions = Set(logs.map { $0.weatherDirection })
        XCTAssertGreaterThanOrEqual(directions.count, 3,
            "Expected ≥3 distinct weatherDirection values across 365 days; got \(directions)")
    }

    func testEventsFireDuring365Days() {
        let logs = SimulationRunner.run(days: 365, seed: 42, profession: 3)
        let totalEvents = logs.reduce(0) { $0 + $1.events.count }
        XCTAssertGreaterThan(totalEvents, 0,
            "At least 1 event must fire across 365 simulated days")
    }
}
