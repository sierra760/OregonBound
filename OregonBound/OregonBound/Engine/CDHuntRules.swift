/// Macintosh CD CODE14 hunting initialization. Kept separate from the classic
/// CODE13 rules: the CD terrain, seasons, population cap, and reseeding differ.
enum CDHuntRules {
    struct Preparation: Equatable {
        let habitat: Int
        let population: [Int]
    }

    /// CODE14:019e–02f4. Terrain depends on unsigned 16-bit mileage; population
    /// starts a fresh TickCount stream. Both changes affect the shared game RNG.
    static func prepare(destination: Int, month: Int, rain: Int, mileage: Int,
                        repeated: Bool, tickSeed: UInt32, reseed: (UInt32) -> Void,
                        random: (Int) -> Int) -> Preparation {
        reseed(UInt32(UInt16(truncatingIfNeeded: mileage)))
        let terrain = habitat(destination: destination,rain: rain,random: random)
        reseed(tickSeed)
        return Preparation(habitat: terrain,population: population(
            destination: destination,month: month,habitat: terrain,repeated: repeated,random: random))
    }

    /// CODE14:01ac–02ee. The rain field is world+230, distinct from weather and snow.
    static func habitat(destination: Int, rain: Int, random: (Int) -> Int) -> Int {
        switch destination {
        case ..<3: return rain > 40 ? (random(2) != 0 ? 0 : 3) : (random(2) != 0 ? 1 : 9)
        case 3...4: return 7
        case 5: return random(2) != 0 ? 7 : 2
        case 6...9:
            if random(2) != 0 { return 4 }
            return random(2) != 0 ? 6 : 2
        case 10...12: return random(2) != 0 ? 4 : 5
        case 13: return 6
        default: return [4,5,8][random(3)]
        }
    }

    /// Eleven sprite classes: 0...6 ground animals, 7...9 flying animals,
    /// 10 tumbleweed. The last class has artwork but no initial population.
    /// CODE14:030a–05f4, before first-visit removal and pruning.
    static func initialWeights(destination d: Int, month: Int, habitat: Int, repeated: Bool) -> [Int] {
        var weights = Array(repeating: 0,count: 11)
        weights[2] = repeated ? 40 : 20
        weights[3] = weights[2]
        if habitat != 2 && habitat != 6 {
            weights[1] = 25
            if d <= 13 { weights[0] = 15 }
        }
        if (4...10).contains(d) || (12...14).contains(d) { weights[6] = 20 }
        if d >= 7 { weights[4] = 15 }
        if (4...10).contains(month) && d > 10 { weights[5] = 10 }
        if d < 5 { weights[8] = (4...10).contains(month) ? 15 : 8 }
        else if d == 5 { weights[8] = 8 }

        if d < 3 {
            if month > 9 || month < 4 { weights[7] = 15 }
        } else if d < 5 {
            if month > 11 || month < 4 { weights[7] = 15 }
        } else if d < 7 { weights[7] = 15 }
        else if month > 10 { weights[7] = 15 }
        else if month < 5 { weights[7] = 8 }

        if d < 2 { weights[9] = (4...10).contains(month) ? 8 : 15 }
        else if d < 3 { weights[9] = 8 }
        else if d < 5 {
            if month == 2 || month == 3 || (9...11).contains(month) { weights[9] = 15 }
            else if (4...8).contains(month) || month == 12 || month == 1 { weights[9] = 8 }
        } else if d < 6 { weights[9] = 8 }
        else if d < 7 {
            if (3...11).contains(month) { weights[9] = 15 }
        } else if d < 10 {
            if (3...11).contains(month) { weights[9] = 8 }
        } else if month > 10 || month < 3 { weights[9] = 15 }
        else if [3,4,9,10].contains(month) { weights[9] = 8 }
        return weights
    }

    /// CODE14:05f6–06d0. Randomly retain three classes. A first visit removes
    /// one small-animal class and protects the last counted large ground class.
    static func population(destination: Int, month: Int, habitat: Int, repeated: Bool,
                           random: (Int) -> Int) -> [Int] {
        var weights = initialWeights(destination: destination,month: month,habitat: habitat,repeated: repeated)
        if !repeated { weights[random(2)+2] = 0 }
        var remaining = weights.filter { $0 != 0 }.count
        // The original count excludes class 6, although its removal guard below
        // includes class 6. Keep that asymmetry and the decrements exactly.
        var largeCount = [0,1,4,5].filter { weights[$0] != 0 }.count
        while remaining > 3 {
            let index = random(11)
            let large = index <= 6 && index != 2 && index != 3
            if large && largeCount <= 1 && !repeated { continue }
            guard weights[index] != 0 else { continue }
            weights[index] = 0
            remaining -= 1
            if large { largeCount -= 1 }
        }
        return weights
    }
}
