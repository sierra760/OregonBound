/// The deterministic health fragment from original CODE 16:0x21a8–0x2482.
/// See docs/ORIGINAL_HEALTH.md. This does not advance a day or run random events.
enum OriginalHealth {
    static let conditionNames = ["Broken Arm", "Broken Leg", "Snakebite", "Exhaustion", "Typhoid", "Cholera", "Measles", "Dysentery", "A Fever"]

    static func conditionCode(illness: String?, alive: Bool) -> UInt8 {
        guard alive else { return 9 }
        guard let illness else { return 255 }
        return UInt8(conditionNames.firstIndex(where: { $0.lowercased() == illness.lowercased() }) ?? 3)
    }

    struct Member: Equatable, Sendable {
        /// Original player+0x61[slot]: 255 healthy, 0...8 condition, 9 deceased.
        var condition: UInt8 = 255
        /// Original player+0x66[slot], decremented as an unsigned byte.
        var remainingDays: UInt8 = 0
    }

    struct Input: Equatable, Sendable {
        var badness: UInt8 = 0                 // player+0x5e
        var auxiliary: UInt8 = 0               // player+0x5f
        var pendingEventPenalty: UInt8 = 0     // player+0x60
        var survivors: UInt8 = 5               // player+0x04
        var food: Int16 = 100                  // player+0x52
        var perishableFood: Int16 = 0          // CD player+0x54
        var edition: GameEdition = .macintosh11
        var clothing: Int16 = 10               // player+0x48
        var rations: UInt8 = 0                 // player+0x02: filling/meager/bare bones
        var pace: UInt8 = 0                    // world+0x04: steady/strenuous/grueling
        /// Flags after the day's rest/delay counters have been processed.
        var stateFlags: UInt8 = 0              // world+0x05; 4 rest, 8 delay
        var temperature: UInt8 = 2             // world+0x22e, category 0...5
        var weather: UInt8 = 0                 // world+0x22d, classic0...9/CD0...10
        /// Include all original slots, including deceased members (player+0x05).
        var members: [Member] = Array(repeating: Member(), count: 5)
    }

    struct Terms: Equatable, Sendable {
        let retainedBadness: Int
        let temperature: Int
        let clothing: Int
        let rations: Int
        let paceAndWeather: Int
        let auxiliary: Int
        let activeConditions: Int
        let pendingEvent: Int

        var sum: Int {
            retainedBadness + temperature + clothing + rations + paceAndWeather
                + auxiliary + activeConditions + pendingEvent
        }
    }

    struct Output: Equatable, Sendable {
        let badness: UInt8
        let auxiliary: UInt8
        let pendingEventPenalty: UInt8
        let food: Int16
        let perishableFood: Int16
        let members: [Member]
        let recoveredMemberIndices: [Int]
        /// Value stored by MOVE.B at 0x2438, before the >139 comparison.
        let storedBadnessBeforeThreshold: UInt8
        /// Caller must invoke the original illness/death action if this is true.
        /// This means greater than 139 after byte wrapping, not a health-band change.
        let thresholdCrossed: Bool
        let terms: Terms
    }

    enum Band: Int, Equatable, Sendable {
        case good = 0, fair = 1, poor = 2, veryPoor = 3
    }

    /// CODE 3:0x30d6–0x30e4 selects STR#3007 using badness/35 +1.
    /// Returns nil for an unrecognized raw value.
    static func band(for badness: UInt8) -> Band? {
        Band(rawValue: Int(badness) / 35)
    }

    /// CODE 10:0x0264–0x0298. Multiply this by the surviving party count.
    static func scorePerSurvivor(badness: UInt8) -> Int {
        500 - (Int(badness) / 35) * 100
    }

    static func transition(_ input: Input) -> Output {
        precondition((1...5).contains(input.survivors), "Requires a living original-size party")
        precondition(input.food >= 0 && input.perishableFood >= 0 && input.clothing >= 0)
        let availableFood = Int(input.food) + (input.edition == .macintoshCD12 ? Int(input.perishableFood) : 0)
        precondition(input.rations <= 2 && input.pace <= 2)
        precondition(input.temperature <= 5 && input.weather <= (input.edition == .macintoshCD12 ? 10 : 9))
        precondition(input.members.count <= 5)

        var members = input.members
        var recovered: [Int] = []
        var activeConditions = 0
        // CODE 16:0x22ee–0x2336 counts BEFORE checking whether recovery occurs.
        for index in members.indices where members[index].condition != 255 && members[index].condition != 9 {
            activeConditions += 1
            members[index].remainingDays &-= 1
            if members[index].remainingDays == 0 {
                members[index].condition = 255
                recovered.append(index)
            }
        }

        let temperature = Int(input.temperature)
        let clothingPenalty = max(0, 5 - 2 * temperature - Int(input.clothing) / Int(input.survivors))
        // Swift integer division truncates toward zero, as CODE 1:0x498c does.
        // In particular (0 -1)/2 must produce zero, not negative one.
        let auxiliary = UInt8(truncatingIfNeeded: (Int(input.auxiliary) - 1) / 2
            + ((clothingPenalty > 0 || availableFood == 0) ? 1 : 0))
        let terms = Terms(
            retainedBadness: Int(min(input.badness, 139)) * 9 / 10,
            temperature: temperature < 3 ? 2 - temperature : temperature - 3,
            clothing: clothingPenalty,
            rations: availableFood > 0 ? 2 * Int(input.rations) : 16,
            paceAndWeather: (input.stateFlags & 0x0c == 0 ? 2 * (Int(input.pace) + 1) : 0)
                + (input.weather >= 3 ? 1 : 0) + (input.weather >= 5 ? 1 : 0),
            auxiliary: Int(auxiliary),
            activeConditions: activeConditions,
            pendingEvent: Int(input.pendingEventPenalty)
        )
        // Original MOVE.B occurs before comparison; do not clamp the Int sum.
        let stored = UInt8(truncatingIfNeeded: terms.sum)
        let need = Int(input.survivors) * (3 - Int(input.rations))
        var food = Int(input.food), perishable = Int(input.perishableFood)
        if input.edition == .macintoshCD12 {
            // CD CODE17:2a36–2ab0: allocate one fifth to stored food, then
            // cover either negative balance from the other supply before clamping.
            food -= need / 5
            perishable -= need - need / 5
            if food < 0 { perishable = max(0, perishable + food); food = 0 }
            if perishable < 0 { food = max(0, food + perishable); perishable = 0 }
        } else {
            food = max(0, food - need)
        }
        return Output(
            badness: min(stored, 139), auxiliary: auxiliary, pendingEventPenalty: 0,
            food: Int16(food), perishableFood: Int16(perishable), members: members, recoveredMemberIndices: recovered,
            storedBadnessBeforeThreshold: stored, thresholdCrossed: stored > 139, terms: terms
        )
    }
}
