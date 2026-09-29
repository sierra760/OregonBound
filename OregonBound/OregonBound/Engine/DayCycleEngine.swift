import Foundation

/// Countdown and weather rules for the legacy simulation (FUN_00001f24).
/// State lives in GameState and the caller's RNG. The playable journey uses
/// JourneyEngine and OriginalDailyWeather instead.
struct DayCycleEngine {

    // MARK: - gameStateFlags bit masks (game_state_block_layout)

    static let flagTimeAdvance: UInt8 = 0x08   // event countdown active
    static let flagAnimalMove:  UInt8 = 0x04   // animal movement (oxen issue)
    static let flagGameOver:    UInt8 = 0x20   // all players dead (FUN_00001b62)

    // MARK: - weatherDirection lock bit

    static let weatherLockMask = 0x80          // bit set on weatherDirection during locked events

    // MARK: - Wind speed constants (weather_system.wind_speeds)

    static let eastModerateSpeed = 20
    static let eastStrongSpeed   = 80
    static let westModerateSpeed = 160
    static let westStrongSpeed   = 640

    // MARK: - Probability constants

    /// RNG(10) < 3 → strong wind (30%), else moderate. Source: FUN_00001f24.
    static let strongWindRNGRange    = 10
    static let strongWindThreshold   = 3

    /// This simulation uses a 50% wind threshold. It does not read the original
    /// A5-resident wind_probability_table.
    static let windPresenceRNGRange  = 1000
    static let windPresenceThreshold = 500

    // MARK: - Countdown Ticks (FUN_00001f24 steps 1–2)

    /// Decrements event and animal countdowns; clears the owning flag when each reaches zero.
    ///
    /// - If gameStateFlags bit 0x08 (flagTimeAdvance) is set: decrement eventCountdown.
    ///   Clear 0x08 if eventCountdown falls to or below 0.
    /// - If gameStateFlags bit 0x04 (flagAnimalMove) is set: decrement animalCountdown.
    ///   Clear 0x04 if animalCountdown falls to or below 0.
    mutating func tickCountdowns(state: inout GameState) {
        if state.gameStateFlags & DayCycleEngine.flagTimeAdvance != 0 {
            state.eventCountdown -= 1
            if state.eventCountdown <= 0 {
                state.gameStateFlags &= ~DayCycleEngine.flagTimeAdvance
            }
        }
        if state.gameStateFlags & DayCycleEngine.flagAnimalMove != 0 {
            state.animalCountdown -= 1
            if state.animalCountdown <= 0 {
                state.gameStateFlags &= ~DayCycleEngine.flagAnimalMove
            }
        }
    }

    // MARK: - Weather State Machine (FUN_00001f24 step 3)

    /// Updates weatherDirection, weatherSeverity, windSpeedEast, and windSpeedWest.
    ///
    /// A weather lock skips this update without consuming randomness. Otherwise,
    /// RNG(2) decides whether to keep the current weather. A new weather state
    /// draws a base direction, severity, then wind presence and strength.
    /// Severity stores the raw RNG(41) result; the original severity table is
    /// not used by this simulation.
    mutating func updateWeather(state: inout GameState, rng: inout LCGRandomNumberGenerator) {
        // Step 1: locked weather — strip lock bit, return without touching RNG
        if state.weatherDirection & DayCycleEngine.weatherLockMask != 0 {
            state.weatherDirection &= ~DayCycleEngine.weatherLockMask
            return
        }

        // Step 2: ~50% chance to keep current weather
        if rng.rng(2) != 0 { return }

        // Step 3: base direction 0-2
        let baseDir = rng.rng(3)

        // The raw roll stands in for the original severity table.
        state.weatherSeverity = rng.rng(41)

        // Step 5: wind presence
        let windRoll = rng.rng(DayCycleEngine.windPresenceRNGRange)
        if windRoll < DayCycleEngine.windPresenceThreshold {
            // East/west uses rng(1000) rather than rng(2) to avoid LCG parity bias — with
            // alternating even/odd state, rng(2) at this position always returns the same parity.
            let isWest   = rng.rng(DayCycleEngine.windPresenceRNGRange) >= DayCycleEngine.windPresenceThreshold
            let isStrong = rng.rng(DayCycleEngine.strongWindRNGRange) < DayCycleEngine.strongWindThreshold
            if isWest {
                state.weatherDirection = isStrong ? 6 : 5
                state.windSpeedEast    = 0
                state.windSpeedWest    = isStrong
                    ? DayCycleEngine.westStrongSpeed
                    : DayCycleEngine.westModerateSpeed
            } else {
                state.weatherDirection = isStrong ? 4 : 3
                state.windSpeedEast    = isStrong
                    ? DayCycleEngine.eastStrongSpeed
                    : DayCycleEngine.eastModerateSpeed
                state.windSpeedWest    = 0
            }
        } else {
            state.weatherDirection = baseDir
            state.windSpeedEast    = 0
            state.windSpeedWest    = 0
        }
    }

    // MARK: - Daily Event Roll (FUN_0000309a) — 9 priority-ordered checks

    static let landmarkTriggerMiles = 3000

    /// Runs all 9 priority-ordered event checks for one simulated day.
    /// Mutates player disease/supply state where events apply.
    /// Returns the structured events that fired.
    mutating func dailyEventRoll(state: inout GameState, rng: inout LCGRandomNumberGenerator) -> [GameEvent] {
        var events: [GameEvent] = []

        // 1. Landmark arrival — deterministic distance threshold
        if state.milesTraveled > DayCycleEngine.landmarkTriggerMiles {
            events.append(.arrivedLandmark)
        }

        // 2. Severe weather exposure per player: 4% → cold/frostbite (disease_type=2, RNG(3)+9 days)
        if state.weatherSeverity > 2 {
            for i in 0..<state.players.count {
                if rng.rng(100) < 4 {
                    state.players[i].diseaseType    = 2
                    state.players[i].diseaseDuration = rng.rng(3) + 9
                    events.append(.coldExposure(playerIndex: i))
                }
            }
        }

        // 3. Per-player: illness roll, wagon breakdown, frontier weather exposure
        for i in 0..<state.players.count {
            // Illness: RNG(100) < illnessRate/15 + 1
            let illnessThreshold = state.players[i].illnessRate / 15 + 1
            if rng.rng(100) < illnessThreshold {
                state.players[i].sickDaysLeft = 20
                events.append(.diseaseMild(playerIndex: i))
            }

            // Wagon breakdown: no spare parts (supply[4]==0) AND 5% chance
            if state.players[i].supply[4] == 0 && rng.rng(100) < 5 {
                events.append(.accidentSupplies(playerIndex: i))
            }

            // Frontier profession weather exposure (professionClass > 4, severity >= 2, 10%)
            if state.professionClass > 4 && state.weatherSeverity >= 2 && rng.rng(100) < 10 {
                state.players[i].diseaseType     = 2
                state.players[i].diseaseDuration = rng.rng(3) + 9
                events.append(.coldExposure(playerIndex: i))
            }
        }

        // 4. Weather travel stop: strong wind deterministic; mild weather 15%
        if state.weatherDirection == 4 || state.weatherDirection == 6 {
            events.append(.stormStop)
        } else if state.weatherSeverity < 2 && rng.rng(100) < 15 {
            events.append(.fogStop)
        }

        // 5. Random travel event: 3% good, 3% bad
        let travelRoll = rng.rng(100)
        if travelRoll < 3 {
            events.append(.goodTravelDay)
        } else if travelRoll < 6 {
            events.append(.badTravelDay)
        }

        // 6. Seasonal event: 7% winter (trailMonth>11), 4% otherwise
        if !state.players.isEmpty {
            let seasonThreshold = state.trailMonth > 11 ? 7 : 4
            if rng.rng(100) < seasonThreshold {
                let playerIdx = rng.rng(state.players.count)
                switch rng.rng(3) {
                case 0:
                    events.append(.theftSupplyStolen(playerIndex: playerIdx, supplyType: rng.rng(7)))
                case 1:
                    events.append(.accidentSupplies(playerIndex: playerIdx))
                default:
                    events.append(.mildInjury(playerIndex: playerIdx))
                }
            }
        }

        // 7. Winter accident check: 5% when trailMonth > 11
        if !state.players.isEmpty && state.trailMonth > 11 {
            if rng.rng(100) < 5 {
                let playerIdx = rng.rng(state.players.count)
                switch rng.rng(3) {
                case 0:
                    events.append(.accidentSupplies(playerIndex: playerIdx))
                case 1:
                    events.append(.lostDays(playerIndex: playerIdx))
                default:
                    events.append(.seriousInjury(playerIndex: playerIdx))
                }
            }
        }

        // 8. Supply find / theft: case 0 → supplies, case 1 → theft
        let supplyTheftRoll = rng.rng(100)
        if supplyTheftRoll == 0 {
            // Find: ammo RNG(40)+20; each other supply type RNG(3)+1
            for i in 0..<state.players.count {
                state.players[i].supply[2] += rng.rng(40) + 20
                for j in 0..<state.players[i].supply.count where j != 2 {
                    state.players[i].supply[j] += rng.rng(3) + 1
                }
                events.append(.suppliesFound(playerIndex: i))
            }
        } else if supplyTheftRoll == 1 {
            // Theft: stolen = RNG(amount)+1, or RNG(100)+1 if amount > 100
            for i in 0..<state.players.count {
                let supplyType    = rng.rng(7)
                let currentAmount = state.players[i].supply[supplyType]
                if currentAmount > 0 {
                    let stolen = currentAmount > 100 ? rng.rng(100) + 1 : rng.rng(currentAmount) + 1
                    state.players[i].supply[supplyType] = max(0, currentAmount - stolen)
                    events.append(.theftSupplyStolen(playerIndex: i, supplyType: supplyType))
                }
            }
        }

        // 9. Fort stop: distanceToNext==0 AND RNG(2)!=0; 40% long rest, else short
        if state.distanceToNext == 0 && rng.rng(2) != 0 {
            events.append(.reachedFort)
            events.append(rng.rng(100) < 40 ? .rest20Days : .rest10Days)
        }

        return events
    }

    // MARK: - Party Resource Check (FUN_000019c2 / FUN_00001b62)

    /// Sums supply[0..6] + extraResource across all active player slots.
    /// If the party-wide total is 0, kills all players in reverse slot order.
    mutating func partyResourceCheck(state: inout GameState) -> [GameEvent] {
        var hasActivePlayers = false
        var totalResources = 0
        for i in 0..<state.playerSlots.count {
            let slotIndex = state.playerSlots[i]
            guard slotIndex != 0xFF else { continue }
            hasActivePlayers = true
            let player = state.players[slotIndex]
            totalResources += player.supply.reduce(0, +) + player.extraResource
        }
        guard hasActivePlayers, totalResources == 0 else { return [] }
        return killAllPlayers(state: &state)
    }

    /// Kills all active players in reverse slot order, then sets the game-over flag.
    /// Implements FUN_00001b62: reverse-slot kill sequence to match original death ordering.
    private mutating func killAllPlayers(state: inout GameState) -> [GameEvent] {
        var events: [GameEvent] = []
        for i in stride(from: state.playerSlots.count - 1, through: 0, by: -1) {
            let slotIndex = state.playerSlots[i]
            guard slotIndex != 0xFF else { continue }
            events.append(.playerDeath(playerIndex: slotIndex))
            state.players[slotIndex].statusFlags = 0
            state.playerSlots[i] = 0xFF
            state.activePartyCount -= 1
        }
        state.gameStateFlags |= DayCycleEngine.flagGameOver
        return events
    }

    // MARK: - Advance Day

    /// Chains all four simulation phases: countdown ticks, weather update, daily event roll,
    /// and party resource check (starvation kill).
    mutating func advanceDay(state: inout GameState, rng: inout LCGRandomNumberGenerator) -> [GameEvent] {
        tickCountdowns(state: &state)
        updateWeather(state: &state, rng: &rng)
        var events = dailyEventRoll(state: &state, rng: &rng)
        events.append(contentsOf: partyResourceCheck(state: &state))
        return events
    }
}
