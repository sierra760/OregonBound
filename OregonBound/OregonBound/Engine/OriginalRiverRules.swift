import Foundation

/// Instruction-derived single-wagon rules. CODE offsets exclude resource header.
/// See ORIGINAL_RIVERS.md for the inherited-D7 defect at Snake River.
enum OriginalRiverRules {
    struct Dimensions: Codable, Equatable {
        var depthHalfFeet: UInt8
        var widthTensFeet: UInt8
        var depthFeet: Double { Double(depthHalfFeet) / 2 }
        var widthFeet: Int { Int(widthTensFeet) * 10 }
    }

    enum Phase: String, Codable { case animation, result }

    struct Outcome: Codable, Equatable {
        var requestedMethodRaw: Int
        var animationMethodRaw: Int
        var failureKind: Int      // A5-1856:0 success,1 swamped,2 tipped
        var status: Int           // A5-1858:0 safe,1 swamped,2 tipped,3 mud,4 wet
        var currentFactor: Int
        var losses: [Int] = Array(repeating: 0, count: 7)
        var drownedMembers: [Int] = []
        var presentationRandomTicks: Int? // CODE3:2296 draw affects future RNG
        // Absent in legacy saves, whose losses were already generated.
        var phase: Phase?
        var isPrepared: Bool { phase != .animation }
    }

    typealias Draw = (_ bound: Int, _ codeOffset: Int) -> Int

    /// CODE16:26ee–2786; no RNG. Both stored dimensions wrap as unsigned bytes.
    static func dimensions(destination: Int, rain: UInt16) -> Dimensions {
        let base: (Int, Int)
        switch destination {
        case 0: base = (2, 600)
        case 1: base = (2, 220)
        case 8: base = (40, 400)
        case 11: base = (12, 1000)
        default: preconditionFailure("Not an original river landmark")
        }
        return Dimensions(depthHalfFeet: UInt8(truncatingIfNeeded: base.0 + Int(rain) / 25),
                          widthTensFeet: UInt8(truncatingIfNeeded: (base.1 + Int(rain) * 3 / 20) / 10))
    }

    static func destinationIndex(_ trip: Journey) -> Int {
        (TrailCatalog.stops.firstIndex { $0.id == trip.locationID } ?? 1) - 1
    }

    /// Optional state preserves a verified arrival snapshot; legacy saves retain
    /// their old dimensions, quantized to original units, until the next arrival.
    static func dimensions(in trip: Journey) -> Dimensions {
        trip.originalRiverDimensions ?? Dimensions(
            depthHalfFeet: UInt8(clamping: Int(trip.riverDepth * 2)),
            widthTensFeet: UInt8(clamping: Int(trip.riverWidth) / 10))
    }

    static func methodRaw(_ method: CrossingMethod) -> Int {
        switch method { case .ford: return 1; case .caulk: return 2; case .ferry: return 3; case .guide: return 4 }
    }

    /// CODE18:00c6–0116: controls hidden by location; depth/cost checks happen
    /// only after selection (0138–0220), so shallow choices remain visible.
    static func availableMethods(destination: Int) -> [CrossingMethod] {
        var methods: [CrossingMethod] = [.ford, .caulk]
        if [0, 8].contains(destination) { methods.append(.ferry) }
        if destination == 11 { methods.append(.guide) }
        return methods
    }

    static func rejection(_ method: CrossingMethod, destination: Int, depthHalfFeet: Int, cash: Int, clothing: Int) -> String? {
        if !availableMethods(destination: destination).contains(method) { return "That crossing method is not available here." }
        if method == .caulk && depthHalfFeet < 3 { return "The river is too shallow to float your wagon across." }
        if method == .ferry {
            if depthHalfFeet < 5 { return "The ferry is not running today because the river is too shallow." }
            if cash < 500 { return "You do not have the $5.00 to pay the ferry operator." }
        }
        if method == .guide && clothing < 3 { return "You do not have the 3 sets of clothing to pay the Indian." }
        return nil
    }

    /// CODE18:1176. Literal switch handles index9, not Snake11. Unmatched
    /// destinations use the incoming signed D7 word; callers must supply it.
    static func currentFactor(destination: Int, rain: UInt16, inheritedD7: Int) -> Int {
        let base: Int
        switch destination { case 0: base = 300; case 1: base = 200; case 8: base = 500; case 9: base = 700
        default: base = Int(Int16(truncatingIfNeeded: inheritedD7)) }
        return (base + Int(rain)) / 100
    }

    /// CODE18:034e outcome branch, then0256 losses, then CODE3:2296 R(180).
    /// Supply inventory must reflect the ferry/guide payment before this call.
    static func resolve(method: CrossingMethod, destination: Int, dimensions: Dimensions,
                        rain: UInt16, inventory: [Int], living: [Bool],
                        inheritedD7: Int = 6, draw: Draw) -> Outcome {
        let choice = choose(method: method, destination: destination, dimensions: dimensions,
                            rain: rain, inheritedD7: inheritedD7, draw: draw)
        return prepareResult(choice, destination: destination, dimensions: dimensions,
                             rain: rain, inventory: inventory, living: living, draw: draw)
    }

    /// CODE18:034e runs before animation. Loss arrays are cleared at0e46.
    static func choose(method: CrossingMethod, destination: Int, dimensions: Dimensions,
                       rain: UInt16, inheritedD7: Int = 6, draw: Draw) -> Outcome {
        let requested = methodRaw(method)
        let depth = Int(dimensions.depthHalfFeet)
        // CODE18:0dcc–0de2 payment loop leaves D7=7 for ferry/guide.
        // Single-wagon options pane is root child ordinal6: CODE6:1c6c,
        // CODE18:0124, CODE5:2eea/3998. Preserve that inherited register.
        let register = requested >= 3 ? 7 : inheritedD7
        let factor = currentFactor(destination: destination, rain: rain, inheritedD7: register)
        var result = Outcome(requestedMethodRaw: requested, animationMethodRaw: requested,
                             failureKind: 0, status: 0, currentFactor: factor, phase: .animation)
        func tip() { result.failureKind = 2; result.status = 2 }
        switch method {
        case .ford:
            if depth < 5 {
                if [8, 11].contains(destination) && draw(100, 0x03b8) < 16 { tip() }
                if destination == 1 && draw(100, 0x03e0) < 40 { result.status = 3 }
            } else if depth == 5 { result.status = 4 }
            else { result.failureKind = 1; result.status = 1 }
        case .caulk:
            if depth >= 5 && draw(100, 0x042a) < factor * 5 { tip() }
        case .ferry:
            if depth >= 5 {
                if factor > 10 { if draw(100, 0x0468) < 10 { tip() } }
                else if factor > 5 { if draw(100, 0x048e) < 5 { tip() } }
            }
        case .guide:
            result.animationMethodRaw = depth < 5 ? 1 : 2
            if depth < 5 {
                if [8, 11].contains(destination) && draw(1000, 0x04d0) < 32 { tip() }
                if destination == 1 && draw(100, 0x04f6) < 8 { result.status = 3 }
            } else if draw(100, 0x0516) < factor { tip() }
        }
        return result
    }

    /// CODE3:228e calls CODE18:0256 at result creation, using live world state.
    /// The shared RNG can advance during queued rest while animation plays.
    static func prepareResult(_ choice: Outcome, destination: Int, dimensions: Dimensions,
                              rain: UInt16, inventory: [Int], living: [Bool], draw: Draw) -> Outcome {
        guard !choice.isPrepared else { return choice }
        precondition(inventory.count == 7 && (1...5).contains(living.count))
        var result = choice
        result.phase = .result
        let depth = Int(dimensions.depthHalfFeet)
        // CODE3:225a–228e invokes loss helper only for status1 or2.
        guard result.status == 1 || result.status == 2 else { return result }
        func supplies(_ threshold: Int) {
            for item in 1...6 where inventory[item] != 0 {
                if draw(100, 0x1608) < threshold { result.losses[item] = draw(inventory[item] + 1, 0x1626) }
            }
        }
        func oxen(_ threshold: Int) {
            var pairsLost = 0
            for _ in 0..<((inventory[0] + 1) / 2) {
                if draw(100, 0x14ce) < threshold { pairsLost += 1 }
            }
            result.losses[0] = min(inventory[0], pairsLost * 2)
        }
        func people(_ threshold: Int) {
            var survivors = living.filter { $0 }.count
            for member in 1..<living.count where living[member] {
                if draw(100, 0x1564) < threshold { result.drownedMembers.append(member); survivors -= 1 }
            }
            // Leader gets a draw only after all other survivors drown.
            if survivors == 1 && living[0] && draw(100, 0x15a4) < threshold { result.drownedMembers.append(0) }
        }
        switch result.animationMethodRaw {
        case 1:
            if depth < 5 { supplies(10 + draw(30, 0x0292)) }
            else {
                supplies(depth * 5)
                if depth > 2 { oxen((depth - 2) * 5) }
                if depth > 5 { people((depth - 5) * 5) }
            }
        case 2:
            // CODE18:025e initializes D7=depth before calling1176 at02f6.
            let lossFactor = currentFactor(destination: destination, rain: rain, inheritedD7: depth)
            supplies((lossFactor + 10) / 4)
            if depth > 6 { people((depth - 6) * 4 / 3) }
        default:
            supplies(80); oxen(50); people(20)
        }
        result.presentationRandomTicks = draw(180, 0x2296) // CODE3, not CODE18
        return result
    }
}
