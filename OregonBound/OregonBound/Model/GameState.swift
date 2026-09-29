import Foundation

/// Top-level game state block (A5-0x2706 in original 68k heap).
/// Covers all 21 named fields from game_state_block_layout in game_loop_constants.json.
struct GameState: Codable, Equatable {
    var startingYear: Int = 0
    var professionClass: Int = 0
    var gameStateFlags: UInt8 = 0
    var eventCountdown: Int = 0
    var animalCountdown: Int = 0
    var activePartyCount: Int = 0
    /// 0xFF (255) = no player selected.
    var currentPlayerIdx: Int = 0xFF
    /// 8 slot indices; 0xFF = empty slot.
    var playerSlots: [Int] = Array(repeating: 0xFF, count: 8)
    var seasonMonth: Int = 0
    var weatherDirection: Int = 0
    var weatherSeverity: Int = 0
    var distanceToNext: Int = 0
    var milesTraveled: Int = 0
    var windSpeedEast: Int = 0
    var windSpeedWest: Int = 0
    var trailMonth: Int = 0
    var origPartySize: Int = 0
    var maxPartySlots: Int = 0
    var targetLocationId: Int = 0
    var targetLocationPos: Int = 0
    /// Up to 32 player records.
    var players: [PlayerState] = []
}

extension GameState {
    /// Creates a new game matching FUN_00000564 / FUN_0000010a initialization logic.
    ///
    /// - profession: 1–8 as decoded from the original profession_class field.
    /// - partySize: number of active players (default 1).
    /// - rng: caller-owned LCG; advanced for weatherDirection, distanceToNext, and
    ///        the doctor headstart bonus (profession == 3 only).
    static func newGame(profession: Int, partySize: Int = 1, rng: inout LCGRandomNumberGenerator) -> GameState {
        var state = GameState()
        state.startingYear = 1848
        state.professionClass = profession
        state.activePartyCount = partySize
        state.origPartySize = partySize
        state.maxPartySlots = 32
        // Slot indices 0..<partySize are filled; remainder stay 0xFF (empty).
        for i in 0..<min(partySize, state.playerSlots.count) {
            state.playerSlots[i] = i
        }
        state.players = (0..<partySize).map { _ in PlayerState() }
        state.weatherDirection = rng.rng(3)
        // Formula from distance_start_formula: (8 - profession) * 100 + RNG(100).
        state.distanceToNext = (8 - profession) * 100 + rng.rng(100)
        // Doctor headstart bonus from doctor_headstart_max_miles (FUN_0000010a).
        if profession == 3 {
            state.milesTraveled += rng.rng(1200)
        }
        state.gameStateFlags = 0x02   // travel mode active
        state.seasonMonth = 3         // April departure
        state.trailMonth = 3
        return state
    }
}
