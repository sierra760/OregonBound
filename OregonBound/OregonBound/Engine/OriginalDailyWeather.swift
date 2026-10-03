/// CODE16:0x1f94–0x21a4 and0x249a–0x259a. See ORIGINAL_DAILY_TRAVEL.md.
enum OriginalDailyWeather {
    struct State: Codable, Equatable {
        var category: UInt8 = 0
        var temperature: UInt8 = 2
        // Only initialization to region0 is proven; no guessed route mapping.
        var region: UInt8 = 0
        var rain: UInt16 = 0
        var snow: UInt16 = 0
        var rainIncrement: UInt16 = 0
        var snowIncrement: UInt16 = 0
        var initialized = false
    }

    static let temperatureBases = [
        [19,23,33,46,55,65,70,68,60,49,35,24],
        [13,18,26,39,49,59,65,63,53,41,27,17],
        [13,17,22,32,42,52,61,59,48,37,23,16],
        [10,14,22,33,42,51,59,57,47,36,21,11],
        [20,26,32,40,48,55,64,62,53,42,30,22],
        [28,33,36,41,47,51,56,56,53,44,36,31]
    ]
    static let precipitationThresholds = [
        [39,42,78,99,144,144,117,120,126,90,57,45],
        [15,15,30,63,90,99,81,66,48,30,15,15],
        [15,15,27,48,63,39,30,18,27,27,21,15],
        [15,21,36,69,75,39,24,15,33,42,24,18],
        [45,39,39,36,36,27,9,9,18,30,39,42],
        [171,123,108,69,63,48,15,30,51,99,162,192]
    ]

    static func initialize(_ state: inout State, month: Int, draw: (Int) -> Int) {
        state.category = UInt8(draw(3))
        state.temperature = UInt8((temperatureBases[Int(state.region)][month - 1] + draw(41)) / 20)
        state.rain = 0; state.snow = 0
        state.rainIncrement = 0; state.snowIncrement = 0
        state.initialized = true
    }

    static func update(_ state: inout State, month: Int, draw: (Int) -> Int) {
        precondition(state.region < 6 && (1...12).contains(month))
        if state.category & 128 != 0 {
            state.category &= 127
            switch state.category {
            case 7: state.rainIncrement = 100
            case 8: state.snowIncrement = 800
            case 9: state.rainIncrement = 50
            default: break
            }
        } else if state.category >= 7 || draw(2) != 0 {
            state.category = UInt8(draw(3))
            state.temperature = UInt8((temperatureBases[Int(state.region)][month - 1] + draw(41)) / 20)
            if draw(1000) < precipitationThresholds[Int(state.region)][month - 1] {
                let heavy = draw(10) < 3
                // Opposite increment persists until a fresh dry branch clears both.
                if state.temperature < 2 {
                    state.category = heavy ? 6 : 5
                    state.snowIncrement = heavy ? 640 : 160
                } else {
                    state.category = heavy ? 4 : 3
                    state.rainIncrement = heavy ? 80 : 20
                }
            } else {
                state.rainIncrement = 0; state.snowIncrement = 0
            }
        }
        state.rain = UInt16(truncatingIfNeeded: Int(state.rain) * 9 / 10 + Int(state.rainIncrement))
        state.snow = UInt16(truncatingIfNeeded: Int(state.snow) * 97 / 100 + Int(state.snowIncrement))
        if state.snow > 0 && (state.temperature >= 3 || state.category == 4) {
            state.rain &+= 50
            if state.snow < 500 { state.snow = 0 }
        }
    }

    static func tickCounters(flags: inout UInt8, rest: inout UInt8, delay: inout Int) {
        if flags & 8 != 0 {
            if delay == 0 { flags &= ~8 } else { delay -= 1 }
        }
        if flags & 4 != 0 {
            if rest == 0 { flags &= ~4 } else { rest &-= 1 }
        }
    }

    // Oxen are the raw inventory word. CODE7 doubles the entered purchase count;
    // six displayed pairs are raw12, capped8 here, and produce20 early miles/day.
    static func movement(flags: UInt8, pace: Int, destination: Int, oxen: Int,
                         conditions: Int, snow: UInt16, remaining: Int) -> Int {
        guard flags & 2 != 0, flags & 12 == 0 else { return 0 }
        let snowFactor = max(0, Int(Int16(truncatingIfNeeded: 4000 - Int(snow))))
        let terrain = destination < 5 ? 20 : 12
        let base = terrain * min(oxen, 8) * (pace + 2) * (10 - conditions) * snowFactor / 640000
        return remaining < base * 11 / 10 ? remaining : base
    }
}

/// Optional on Journey so saves written before original-state integration decode.
struct OriginalJourneyState: Codable, Equatable {
    var badness: UInt8 = 0
    var auxiliary: UInt8 = 0
    var pendingEventPenalty: UInt8 = 0
    var flags: UInt8 = 0
    var restDays: UInt8 = 0
    var lastMovement: UInt8 = 0
    /// CD player+6e, recomputed by each active model timer pulse.
    var cdWagonWeight: Int?
    var lastSuccessfulHuntMileage: Int?
    var weather = OriginalDailyWeather.State()
}
