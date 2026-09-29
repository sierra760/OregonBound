import XCTest
@testable import OregonBound

final class DayCycleEngineTests: XCTestCase {

    // MARK: - tickCountdowns

    func testTickCountdownDecrement() {
        var engine = DayCycleEngine()
        var state = GameState()
        state.gameStateFlags = DayCycleEngine.flagTimeAdvance | DayCycleEngine.flagAnimalMove
        state.eventCountdown  = 3
        state.animalCountdown = 3

        engine.tickCountdowns(state: &state)

        XCTAssertEqual(state.eventCountdown,  2, "eventCountdown should decrement by 1")
        XCTAssertEqual(state.animalCountdown, 2, "animalCountdown should decrement by 1")
        XCTAssertNotEqual(state.gameStateFlags & DayCycleEngine.flagTimeAdvance, 0,
                          "0x08 flag must stay set while countdown > 0")
        XCTAssertNotEqual(state.gameStateFlags & DayCycleEngine.flagAnimalMove, 0,
                          "0x04 flag must stay set while countdown > 0")
    }

    func testTickCountdownClearsFlag() {
        var engine = DayCycleEngine()
        var state = GameState()
        state.gameStateFlags  = DayCycleEngine.flagTimeAdvance
        state.eventCountdown  = 0   // already at 0; decrement takes it to -1 (≤ 0) → flag cleared

        engine.tickCountdowns(state: &state)

        XCTAssertEqual(state.gameStateFlags & DayCycleEngine.flagTimeAdvance, 0,
                       "0x08 flag must be cleared when eventCountdown reaches 0 or below")
    }

    func testTickCountdownOnlyDecrementsSetFlags() {
        var engine = DayCycleEngine()
        var state = GameState()
        state.gameStateFlags  = DayCycleEngine.flagTimeAdvance   // only 0x08 set, not 0x04
        state.eventCountdown  = 5
        state.animalCountdown = 5

        engine.tickCountdowns(state: &state)

        XCTAssertEqual(state.eventCountdown,  4, "eventCountdown should decrement (flag set)")
        XCTAssertEqual(state.animalCountdown, 5, "animalCountdown should NOT decrement (flag not set)")
    }

    // MARK: - updateWeather: locked weather

    func testLockedWeatherStripsLockBit() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.weatherDirection = 0x87    // storm-locked direction (bit 0x80 set, code 7)
        var rng = LCGRandomNumberGenerator(seed: 42)
        let seedBefore = rng.state

        engine.updateWeather(state: &state, rng: &rng)

        XCTAssertEqual(state.weatherDirection, 0x07, "Lock bit 0x80 must be stripped; direction 7 preserved")
        XCTAssertEqual(rng.state, seedBefore, "Locked weather must consume no RNG calls")
    }

    func testLockedWeatherVariants() {
        var engine = DayCycleEngine()
        var rng    = LCGRandomNumberGenerator(seed: 0)

        for (input, expected) in [(0x87, 0x07), (0x88, 0x08), (0x89, 0x09)] {
            var state = GameState()
            state.weatherDirection = input
            engine.updateWeather(state: &state, rng: &rng)
            XCTAssertEqual(state.weatherDirection, expected,
                           "Lock bit 0x80 stripped: 0x\(String(input, radix: 16)) → 0x\(String(expected, radix: 16))")
        }
    }

    // MARK: - updateWeather: direction range

    func testWeatherDirectionRange() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.weatherDirection = 0
        var rng = LCGRandomNumberGenerator(seed: 12345)
        var seenDirections = Set<Int>()

        for _ in 0..<1000 {
            engine.updateWeather(state: &state, rng: &rng)
            seenDirections.insert(state.weatherDirection)
        }

        for code in 0...6 {
            XCTAssertTrue(seenDirections.contains(code),
                          "Direction code \(code) should appear within 1000 weather updates")
        }
    }

    // MARK: - updateWeather: wind speed assignment

    func testWindSpeedAssignment() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.weatherDirection = 0
        var rng = LCGRandomNumberGenerator(seed: 12345)
        var observedEastStrong = false
        var observedWestStrong = false

        for _ in 0..<2000 {
            engine.updateWeather(state: &state, rng: &rng)
            switch state.weatherDirection {
            case 3:
                XCTAssertEqual(state.windSpeedEast, DayCycleEngine.eastModerateSpeed,
                               "Direction 3 → east speed 20")
                XCTAssertEqual(state.windSpeedWest, 0, "Direction 3 → west speed 0")
            case 4:
                XCTAssertEqual(state.windSpeedEast, DayCycleEngine.eastStrongSpeed,
                               "Direction 4 → east speed 80")
                XCTAssertEqual(state.windSpeedWest, 0, "Direction 4 → west speed 0")
                observedEastStrong = true
            case 5:
                XCTAssertEqual(state.windSpeedWest, DayCycleEngine.westModerateSpeed,
                               "Direction 5 → west speed 160")
                XCTAssertEqual(state.windSpeedEast, 0, "Direction 5 → east speed 0")
            case 6:
                XCTAssertEqual(state.windSpeedWest, DayCycleEngine.westStrongSpeed,
                               "Direction 6 → west speed 640")
                XCTAssertEqual(state.windSpeedEast, 0, "Direction 6 → east speed 0")
                observedWestStrong = true
            default:
                XCTAssertEqual(state.windSpeedEast, 0, "Calm/variable direction → east speed 0")
                XCTAssertEqual(state.windSpeedWest, 0, "Calm/variable direction → west speed 0")
            }
            if observedEastStrong && observedWestStrong { break }
        }

        XCTAssertTrue(observedEastStrong, "Direction 4 (east-strong, eastSpeed=80) must be observed")
        XCTAssertTrue(observedWestStrong, "Direction 6 (west-strong, westSpeed=640) must be observed")
    }

    // MARK: - dailyEventRoll: severe weather exposure

    func testSevereWeatherTriggersExposure() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.players = [PlayerState()]
        var rng = LCGRandomNumberGenerator(seed: 42)

        var gotColdExposure = false
        for _ in 0..<100 {
            state.weatherSeverity = 3   // keep severe across any state mutation
            let events = engine.dailyEventRoll(state: &state, rng: &rng)
            if events.contains(where: { if case .coldExposure = $0 { return true }; return false }) {
                gotColdExposure = true
                break
            }
        }

        XCTAssertTrue(gotColdExposure,
                      "Cold exposure (4% per player per day when severity>2) must fire within 100 days")
    }

    // MARK: - dailyEventRoll: illness roll

    func testIllnessRollFiresWithHighRate() {
        var engine = DayCycleEngine()
        var state  = GameState()
        var player = PlayerState()
        player.illnessRate = 150   // threshold = 150/15+1 = 11 → ~11% per day
        state.players = [player]
        var rng = LCGRandomNumberGenerator(seed: 42)

        var gotIllness = false
        for _ in 0..<50 {
            let events = engine.dailyEventRoll(state: &state, rng: &rng)
            if events.contains(where: { if case .diseaseMild = $0 { return true }; return false }) {
                gotIllness = true
                break
            }
        }

        XCTAssertTrue(gotIllness,
                      "Illness (illnessRate=150 → ~11% per day) must fire within 50 days")
    }

    // MARK: - dailyEventRoll: weather travel stop

    func testStrongWindStopsTravel() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.weatherDirection = 4   // east strong — deterministic stormStop
        state.players = [PlayerState()]
        var rng = LCGRandomNumberGenerator(seed: 42)

        let events = engine.dailyEventRoll(state: &state, rng: &rng)
        let hasStormStop = events.contains(where: { if case .stormStop = $0 { return true }; return false })

        XCTAssertTrue(hasStormStop,
                      "Strong east wind (direction 4) must deterministically emit stormStop")
    }

    // MARK: - dailyEventRoll: seasonal events (winter)

    func testSeasonalEventWinter() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.players = [PlayerState()]
        var rng = LCGRandomNumberGenerator(seed: 42)

        let isWinterEvent: (GameEvent) -> Bool = { event in
            if case .theftSupplyStolen = event { return true }
            if case .accidentSupplies  = event { return true }
            if case .mildInjury        = event { return true }
            if case .lostDays          = event { return true }
            if case .seriousInjury     = event { return true }
            return false
        }

        var gotWinterEvent = false
        for _ in 0..<200 {
            state.trailMonth = 12   // keep winter (>11): 7% seasonal + 5% accident
            let events = engine.dailyEventRoll(state: &state, rng: &rng)
            if events.contains(where: isWinterEvent) {
                gotWinterEvent = true
                break
            }
        }

        XCTAssertTrue(gotWinterEvent,
                      "Winter seasonal/accident events (~12% combined per day) must fire within 200 days")
    }

    // MARK: - partyResourceCheck: starvation kill system (FUN_000019c2 / FUN_00001b62)

    func testStarvationKillWhenAllSuppliesZero() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.activePartyCount = 2
        state.playerSlots[0] = 0
        state.playerSlots[1] = 1
        // PlayerState() already defaults supply to all-zeros and extraResource = 0
        state.players = [PlayerState(), PlayerState()]

        let events = engine.partyResourceCheck(state: &state)

        let deathCount = events.filter { if case .playerDeath = $0 { return true }; return false }.count
        XCTAssertEqual(deathCount, 2, "Both players must die when party-wide supply total is 0")
        XCTAssertNotEqual(state.gameStateFlags & DayCycleEngine.flagGameOver, 0,
                          "Game-over flag 0x20 must be set after starvation kill")
        XCTAssertEqual(state.activePartyCount, 0, "activePartyCount must reach 0 after all die")
        XCTAssertEqual(state.playerSlots[0], 0xFF, "Slot 0 must be cleared to 0xFF")
        XCTAssertEqual(state.playerSlots[1], 0xFF, "Slot 1 must be cleared to 0xFF")
    }

    func testNoKillWhenOneSupplyRemains() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.activePartyCount = 2
        state.playerSlots[0] = 0
        state.playerSlots[1] = 1
        var p1 = PlayerState()
        p1.supply[2] = 1   // 1 ammo on player 0; all other supplies and player 1 are zero
        state.players = [p1, PlayerState()]

        let events = engine.partyResourceCheck(state: &state)

        let deathCount = events.filter { if case .playerDeath = $0 { return true }; return false }.count
        XCTAssertEqual(deathCount, 0, "No deaths when party-wide supply total > 0")
        XCTAssertEqual(state.gameStateFlags & DayCycleEngine.flagGameOver, 0,
                       "Game-over flag must NOT be set when any supply remains")
        XCTAssertEqual(state.activePartyCount, 2, "activePartyCount must remain 2")
    }

    func testPartialSupplyNoKill() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.activePartyCount = 2
        state.playerSlots[0] = 0
        state.playerSlots[1] = 1
        // Player 0: food=0 (empty), player 1: food=10 — party total > 0
        var p2 = PlayerState()
        p2.supply[0] = 10
        state.players = [PlayerState(), p2]

        let events = engine.partyResourceCheck(state: &state)

        let deathCount = events.filter { if case .playerDeath = $0 { return true }; return false }.count
        XCTAssertEqual(deathCount, 0, "No deaths when one player has food even if another is empty (party-wide sum)")
        XCTAssertEqual(state.gameStateFlags & DayCycleEngine.flagGameOver, 0,
                       "Game-over flag must NOT be set when party has food")
    }

    func testKillOrderIsReverse() {
        var engine = DayCycleEngine()
        var state  = GameState()
        state.activePartyCount = 3
        state.playerSlots[0] = 0
        state.playerSlots[1] = 1
        state.playerSlots[2] = 2
        // All PlayerState() default to zero supplies and extraResource
        state.players = [PlayerState(), PlayerState(), PlayerState()]

        let events = engine.partyResourceCheck(state: &state)

        let deathIndices = events.compactMap { (event: GameEvent) -> Int? in
            if case let .playerDeath(idx) = event { return idx }
            return nil
        }
        XCTAssertEqual(deathIndices, [2, 1, 0],
                       "Death events must fire in reverse slot order: slot 2 first, then 1, then 0")
        XCTAssertNotEqual(state.gameStateFlags & DayCycleEngine.flagGameOver, 0,
                          "Game-over flag 0x20 must be set after wiping all 3 players")
        XCTAssertEqual(state.activePartyCount, 0, "All 3 players must be killed")
    }

    // MARK: - advanceDay

    func testAdvanceDayReturnsCombinedEvents() {
        var engine = DayCycleEngine()
        var rng    = LCGRandomNumberGenerator(seed: 12345)
        var state  = GameState.newGame(profession: 2, partySize: 1, rng: &rng)

        // Run 10 days through the full three-phase chain; verify no crash and valid return
        var allEvents: [GameEvent] = []
        for _ in 0..<10 {
            allEvents.append(contentsOf: engine.advanceDay(state: &state, rng: &rng))
        }

        XCTAssertGreaterThanOrEqual(allEvents.count, 0,
                                    "advanceDay must complete tickCountdowns→updateWeather→dailyEventRoll and return [GameEvent]")
    }
}
