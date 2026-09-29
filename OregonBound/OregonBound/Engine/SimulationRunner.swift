import Foundation

/// Per-day record from a headless simulation run.
struct DayLog: Equatable {
    let dayNumber: Int
    let weatherDirection: Int
    let weatherSeverity: Int
    let events: [GameEvent]
    let activePartyCount: Int
    let milesTraveled: Int
    let isGameOver: Bool
}

/// Runs DayCycleEngine without a UI, using a fixed random seed.
struct SimulationRunner {

    /// Starting supplies for headless simulation runs: food, medicine, ammo, clothing,
    /// spareParts, fodder, goods. This legacy simulation does not consume food.
    static let defaultStartingSupply: [Int] = [200, 10, 100, 20, 5, 50, 30]

    /// Runs up to `days` simulated days with a deterministic seed.
    ///
    /// Creates a new game via GameState.newGame, seeds players with defaultStartingSupply,
    /// then loops calling advanceDay. Breaks early if the game-over flag (0x20) fires.
    ///
    /// - Returns: one DayLog per day advanced; may be shorter than `days` on early game-over.
    static func run(days: Int, seed: UInt32, profession: Int) -> [DayLog] {
        guard days > 0 else { return [] }
        var rng = LCGRandomNumberGenerator(seed: seed)
        var state = GameState.newGame(profession: profession, rng: &rng)
        for i in 0..<state.players.count {
            state.players[i].supply = defaultStartingSupply
        }
        var engine = DayCycleEngine()
        var logs: [DayLog] = []
        logs.reserveCapacity(days)

        for day in 1...days {
            let events = engine.advanceDay(state: &state, rng: &rng)
            logs.append(DayLog(
                dayNumber: day,
                weatherDirection: state.weatherDirection,
                weatherSeverity: state.weatherSeverity,
                events: events,
                activePartyCount: state.activePartyCount,
                milesTraveled: state.milesTraveled,
                isGameOver: state.gameStateFlags & DayCycleEngine.flagGameOver != 0
            ))
            if state.gameStateFlags & DayCycleEngine.flagGameOver != 0 { break }
        }
        return logs
    }
}
