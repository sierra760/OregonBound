import Foundation

/// CD CODE17's illustrated notices use separate event codes from the journal.
/// Selection does not consume gameplay randomness or choose from message text.
enum CDNotificationRules {
    struct Event: Equatable, Codable {
        let code: Int
        var parameter: Int = 0
    }
    struct Context: Equatable {
        let weather: Int
        let snow: Int
        let destination: Int
    }
    struct Selection: Equatable {
        let event: Int
        let art: Int
        let guide: Int
        let sound: Int
        let external: Bool
        let cycle: Bool
        let priority: Bool
        let low: Bool
    }

    struct State {
        private(set) var selected: Selection?
        private var lastSound = 0
        private var lastDestination: [Int: Int] = [:]
        private var foodAid = 0
        private var snowyFoodAid = 0

        /// CODE17:253c resets daily selection; destination guards and the
        /// candidate's sound field survive. The dispatch loop resets variants.
        mutating func beginBatch() {
            selected = nil
            foodAid = 0
            snowyFoodAid = 0
        }

        mutating func receive(_ event: Event, in context: Context) {
            let snow = context.snow > 0
            let weather = context.weather > 1
            var art: Int?
            var guide = 0
            var sound: Int?
            var external = false
            var cycle = false
            let low = [9,10,11,25].contains(event.code)
            if low {
                guard (lastDestination[event.code] ?? 0) != context.destination else { return }
                lastDestination[event.code] = context.destination
            }
            switch event.code {
            case 0: art = 0; sound = 4005; external = true
            case 1: art = 8; sound = 4003; external = true
            case 2: art = snow ? 55 : 54; sound = 4001
            case 3: art = snow ? 53 : 47; sound = 4001
            case 4: art = snow ? 57 : 46; sound = 4001
            case 5: art = snow ? 27 : 7; sound = 4001; cycle = true
            case 6: art = 44; sound = 4001
            case 7: art = 14; guide = 20; sound = 4002; external = true
            case 8: art = 50; sound = 4004; external = true; cycle = true
            case 9: art = snow ? 13 : 11; sound = 4001
            case 10: art = snow ? (weather ? 37 : 36) : 38; sound = 4001
            case 11: art = weather ? 12 : (snow ? 15 : 4); sound = 4001
            case 12: art = 44 // Source leaves the candidate sound untouched.
            case 13: art = 3; sound = 4001
            case 20:
                if snow {
                    art = [32,34][snowyFoodAid]
                    snowyFoodAid = (snowyFoodAid + 1) % 2
                } else {
                    art = [28,29,30,31,33,35][foodAid]
                    foodAid = (foodAid + 1) % 6
                }
                sound = 4000
            case 21: art = snow ? 39 : 10; sound = 4001
            case 23: art = snow ? 45 : 6; sound = 4001
            case 24:
                art = [3,4].contains(context.weather) ? 22 : (weather ? 24 : (snow ? 23 : 25))
                sound = 4001
            case 25: art = 26; sound = 4000
            case 26:
                if event.parameter == 0 { art = 18 }
                else if event.parameter == 1 { art = weather ? 61 : (snow ? 52 : 17) }
                sound = 4001
            case 28: art = weather ? 42 : (snow ? 40 : 41); sound = 4001
            case 29: art = 2; guide = 61; sound = 4007; external = true
            case 37:
                art = 60; guide = [3:19,4:66,5:16,6:45,7:21][event.parameter] ?? 0
                sound = 4001
            case 47:
                switch event.parameter {
                case 3: art = snow ? 56 : 21
                case 4: art = snow ? 59 : 19
                case 5: art = snow ? 58 : 20; guide = 68
                default: break
                }
                sound = 4012
            case 63: art = snow ? 51 : 49; sound = 4000
            case 64: art = snow ? 43 : 5; sound = 4001; cycle = true
            case 65: art = snow ? 48 : 1; sound = 4001; cycle = true
            case 69: art = 62; sound = 4001
            default: return
            }
            // Candidate state updates even when priority rejects its display.
            if let sound { lastSound = sound }
            guard let art else { return }
            let priority = [23,24,26,29,37].contains(event.code)
            let candidate = Selection(event: event.code, art: art, guide: guide, sound: lastSound,
                external: external, cycle: cycle, priority: priority, low: low)
            if priority { selected = candidate }
            else if low {
                if selected == nil || selected?.low == true { selected = candidate }
            } else if selected?.priority != true { selected = candidate }
        }
    }
}
