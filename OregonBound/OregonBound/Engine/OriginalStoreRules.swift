import Foundation

/// Later-game CODE7 Buy branch (A5−309a=0). Counts are entered purchase units:
/// whole displayed oxen, boxes of20 bullets, other supplies singly, food pounds.
enum OriginalStoreRules {
    static let basePrices = [2000, 1000, 200, 1000, 1000, 1000, 20]
    static let capacities = [40, 50, 1980, 3, 3, 3, 2000]
    static let inputDigits = [2, 2, 2, 1, 1, 1, 4]
    /// CD CODE8:0182–01c6 selects the later store's regional backdrop.
    /// Initial outfitting uses the separate view and always selects base0.
    static func artworkResource(in trip: Journey) -> Int {
        guard trip.edition == .macintoshCD12,
              let index = TrailCatalog.stops.firstIndex(where: { $0.id == trip.locationID }) else { return 19030 }
        let destination = index - 1
        let variant: Int
        switch destination {
        case -1: variant = 0
        case ..<3: variant = 4
        case ..<5: variant = 2
        case ..<11: variant = 3
        case ..<13: variant = 1
        default: variant = 5
        }
        return 19030 + variant
    }
    private static let entryLimits = [99, 99, 99, 9, 9, 9, 9999]
    private static let storeIDs: Set<String> = ["independence", "kearney", "laramie", "bridger", "hall", "boise", "walla"]

    enum Rejection: Error, Equatable, LocalizedError {
        case unavailable, invalidQuantity, insufficientMoney
        case capacity(item: Int, quantity: Int)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "You can only buy supplies at forts."
            case .invalidQuantity: return "Enter a valid quantity for each item."
            case .insufficientMoney: return "I’m afraid you don’t have enough money to pay for all those things you’re trying to buy.  You’ll have to go back and buy less."
            case .capacity(let item, let quantity):
                let named = OriginalTradingRules.description(item: item, quantity: quantity)
                let words = named.split(separator: " ", maxSplits: 1).map(String.init)
                let count = OriginalStoreRules.grouped(quantity), label = words.count == 2 ? words[1] : ""
                if item == 0 { return "I’m afraid there won't be enough grass along the trail for \(count) more \(label).  You’ll have to go back and buy less." }
                return "I’m afraid there’s not enough room in your wagon to carry \(count) more \(label).  You’ll have to go back and buy less."
            }
        }
        var dialogResource: Int {
            switch self {
            case .insufficientMoney: return 9032
            case .capacity(let item, _): return item == 0 ? 9034 : 9033
            default: return 9033
            }
        }
    }
    struct Purchase: Equatable {
        let counts: [Int]
        let rawAdditions: [Int]
        let costs: [Int]
        var total: Int { costs.reduce(0, +) }
    }

    static func isAvailable(in trip: Journey) -> Bool {
        trip.phase == .landmark && storeIDs.contains(trip.locationID) &&
        trip.originalRiverOutcome == nil && trip.originalTradeSession == nil
    }
    static func rawQuantity(item: Int, count: Int) -> Int {
        guard (0..<7).contains(item), (0...9999).contains(count) else { return 0 }
        return count * (item == 0 ? 2 : item == 2 ? 20 : 1)
    }
    static func rowCost(item: Int, count: Int, in trip: Journey) -> Int {
        guard (0..<7).contains(item), (0...9999).contains(count) else { return 0 }
        return basePrices[item] * count * TrailCatalog.pricePercent(at: trip.locationID) / 100
    }
    static func have(in trip: Journey) -> [Int] {
        var quantities = Supply.allCases.map { trip.inventory[$0] }
        if trip.inventoryUnitsVersion == nil { quantities[0] *= 2 }
        quantities[0] = (quantities[0] + 1) / 2
        quantities[2] /= 20
        return quantities
    }
    /// CODE1:0a52/0ad0: comma-separated integer part, two cent digits.
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
    static func money(_ cents: Int) -> String {
        grouped(cents / 100) + String(format: ".%02d", abs(cents % 100))
    }

    static func storeName(in trip: Journey) -> String {
        (trip.locationID == "independence" ? "Matt’s" : trip.location.name) + " General Store"
    }

    static func quote(_ counts: [Int], in trip: Journey) throws -> Purchase {
        guard isAvailable(in: trip) else { throw Rejection.unavailable }
        guard counts.count == 7, counts.enumerated().allSatisfy({ (0...entryLimits[$0.offset]).contains($0.element) }) else {
            throw Rejection.invalidQuantity
        }
        var remaining = trip.cash
        var costs: [Int] = [], raw: [Int] = []
        for item in 0..<7 {
            let cost = rowCost(item: item, count: counts[item], in: trip)
            remaining -= cost
            // CODE7:0416 checks cumulative payment BEFORE this row's capacity.
            guard remaining >= 0 else { throw Rejection.insufficientMoney }
            let addition = rawQuantity(item: item, count: counts[item])
            var current = trip.inventory[Supply.allCases[item]]
            if item == 0 && trip.inventoryUnitsVersion == nil { current *= 2 }
            guard current <= capacities[item] - addition else {
                throw Rejection.capacity(item: item, quantity: item == 0 ? counts[item] : addition)
            }
            costs.append(cost); raw.append(addition)
        }
        return Purchase(counts: counts, rawAdditions: raw, costs: costs)
    }

    /// Validates all seven rows before applying anything. CODE7:0510 treats an
    /// empty cart as dismissal, with no purchase journal/model action.
    @discardableResult static func buy(_ counts: [Int], in trip: inout Journey) throws -> Purchase {
        let purchase = try quote(counts, in: trip)
        guard purchase.total > 0 else { return purchase }
        var next = trip
        next.ensureOriginalState()
        for item in 0..<7 { next.inventory[Supply.allCases[item]] += purchase.rawAdditions[item] }
        next.cash -= purchase.total
        let items = (0..<7).filter { counts[$0] > 0 }.map { item in
            OriginalTradingRules.description(item: item, quantity: item == 0 ? counts[item] : purchase.rawAdditions[item])
        }
        next.record("You bought \(items.joined(separator: ", ")) at the store")
        trip = next
        return purchase
    }
}
