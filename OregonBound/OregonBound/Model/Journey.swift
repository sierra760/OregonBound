import Foundation

enum Profession: String, Codable, CaseIterable, Identifiable {
    case banker = "Banker", blacksmith = "Blacksmith", carpenter = "Carpenter", doctor = "Doctor"
    case farmer = "Farmer", merchant = "Merchant", saddlemaker = "Saddlemaker", teacher = "Teacher"
    var id: String { rawValue }
    // CODE 21 initialized A5 data: starting cash at -0x2868, score factors at -0x2b36.
    var startingCash: Int {
        switch self {
        case .banker: return 160_000
        case .merchant, .doctor: return 120_000
        case .blacksmith, .carpenter, .saddlemaker: return 80_000
        case .farmer, .teacher: return 40_000
        }
    }
    var scoreHalfMultiplier: Int {
        switch self {
        case .banker, .doctor: return 2
        case .blacksmith, .carpenter: return 4
        case .farmer: return 6
        case .merchant: return 3
        case .saddlemaker: return 5
        case .teacher: return 7
        }
    }
    var scoreMultiplierText: String { scoreHalfMultiplier.isMultiple(of: 2) ? "\(scoreHalfMultiplier / 2)" : "\(scoreHalfMultiplier / 2).5" }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case greenhorn = "Greenhorn", adventurer = "Adventurer", trailGuide = "Trail Guide"
    var id: String { rawValue }
    var level: Int { Self.allCases.firstIndex(of: self)! }
}

enum Pace: String, Codable, CaseIterable, Identifiable {
    case steady = "Steady", strenuous = "Strenuous", grueling = "Grueling"
    var id: String { rawValue }
    var originalIndex: UInt8 { self == .steady ? 0 : self == .strenuous ? 1 : 2 }
}

enum Rations: String, Codable, CaseIterable, Identifiable {
    case filling = "Filling", meager = "Meager", bareBones = "Bare Bones"
    var id: String { rawValue }
    var pounds: Int { self == .filling ? 3 : self == .meager ? 2 : 1 }
    var originalIndex: UInt8 { self == .filling ? 0 : self == .meager ? 1 : 2 }
}

enum Supply: String, Codable, CaseIterable, Identifiable {
    case oxen, clothing, bullets, wheels, axles, tongues, food
    var id: String { rawValue }
    var title: String {
        switch self {
        case .oxen: return "Oxen"
        case .clothing: return "Sets of clothing"
        case .bullets: return "Bullets"
        case .wheels: return "Wagon wheels"
        case .axles: return "Wagon axles"
        case .tongues: return "Wagon tongues"
        case .food: return "Pounds of food"
        }
    }
    var unitPrice: Int {
        switch self {
        case .oxen: return 2000
        case .clothing, .wheels, .axles, .tongues: return 1000
        case .bullets: return 10
        case .food: return 20
        }
    }
    var packSize: Int { self == .food ? 100 : self == .bullets ? 20 : 1 }
    // Purchase controls count oxen pairs; player+0x46 stores individual oxen.
    var purchaseCapacity: Int { self == .oxen ? capacity / 2 : capacity }
    var capacity: Int {
        switch self {
        case .oxen: return 40
        case .clothing: return 50
        case .bullets: return 1980
        case .food: return 2000
        case .wheels, .axles, .tongues: return 3
        }
    }
}

struct Inventory: Codable, Equatable {
    private var quantities: [String: Int] = [:]
    static let perishableFoodCapacity = 1000
    /// CD player+54. Absent in legacy saves; the existing food key stays stored food.
    var perishableFood: Int {
        get { quantities["perishableFood", default: 0] }
        set { quantities["perishableFood"] = max(0, newValue) }
    }
    subscript(_ supply: Supply) -> Int {
        get { quantities[supply.rawValue, default: 0] }
        set { quantities[supply.rawValue] = max(0, newValue) }
    }
    var valid: Bool { quantities.allSatisfy { key, value in
        if key == "perishableFood" { return (0...Self.perishableFoodCapacity).contains(value) }
        guard let supply = Supply(rawValue: key) else { return false }
        // Previously released saves allowed40 display pairs. Preserve their raw
        // count80 on migration; new purchases still enforce original capacity40.
        return (0...(supply == .oxen ? 80 : supply.capacity)).contains(value)
    } }
}

struct PartyMember: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var health: Double = 100
    var illness: String?
    var sickDays: Int = 0
    var alive: Bool { health > 0 }
    var condition: String {
        if !alive { return "Deceased" }
        return illness ?? (health >= 70 ? "Good" : health >= 45 ? "Fair" : health >= 20 ? "Poor" : "Very Poor")
    }
}

enum JourneyPhase: String, Codable { case outfitting, departure, travel, landmark, river, fork, hunting, rafting, finished }
enum Weather: String, Codable { case sunny = "Sunny", rain = "Rainy", hot = "Hot", cold = "Cold", snow = "Snowy", storm = "Thunderstorm" }

struct JournalEntry: Codable, Equatable, Identifiable {
    var id: Int
    var day: Int
    var text: String
    /// Nil in older native saves; never infer an original face from the prose.
    var originalBold: Bool? = nil
}

struct Journey: Codable, Equatable {
    var edition: GameEdition?
    var gameEdition: GameEdition { edition ?? .macintosh11 }
    var totalFood: Int { inventory[.food] + (gameEdition == .macintoshCD12 ? inventory.perishableFood : 0) }
    var huntingFoodCapacity: Int { gameEdition == .macintoshCD12 ? Inventory.perishableFoodCapacity : Supply.food.capacity }
    var huntingFood: Int {
        get { gameEdition == .macintoshCD12 ? inventory.perishableFood : inventory[.food] }
        set {
            if gameEdition == .macintoshCD12 { inventory.perishableFood = newValue }
            else { inventory[.food] = newValue }
        }
    }
    var id = UUID()
    var profession: Profession
    var difficulty: Difficulty
    var members: [PartyMember]
    var departureMonth: Int
    var daysElapsed = 0
    var cash: Int
    var inventory = Inventory()
    var phase: JourneyPhase = .outfitting
    var locationID = "independence"
    var destinationID: String? = "kansas"
    var legDistance = 102
    var legProgress = 0
    var miles = 0
    var pace: Pace = .steady
    var rations: Rations = .filling
    var weather: Weather = .sunny
    var riverDepth = 3.0
    var riverWidth = 600
    var originalTiming: OriginalPreferences.Timing?
    var timing: OriginalPreferences.Timing { originalTiming ?? .init() }
    var originalRiverDimensions: OriginalRiverRules.Dimensions?
    var originalRiverOutcome: OriginalRiverRules.Outcome?
    var originalRaftState: OriginalRaftSession.JourneyState?
    var originalTradeSession: OriginalTradingRules.Session?
    var originalEndingStage: OriginalEndingStage?
    var originalMapSuppressedLandmarkID: String?
    var delayDays = 0
    var brokenPart: Supply?
    // Original status has independent wheel/axle/tongue bits. Optional additions
    // retain synthesized Codable compatibility with old single-part saves.
    var additionalBrokenParts: [Supply]?
    var originalCashOverdraft: Bool?
    var randomState: UInt32
    var original: OriginalJourneyState?
    var inventoryUnitsVersion: Int?
    var legacyOxenLimit: Int?
    var journal: [JournalEntry] = []
    var visited = ["independence"]
    var won = false
    var finishReason = ""
    var miniGameReturnPhase: JourneyPhase = .travel

    init(profession: Profession = .banker, difficulty: Difficulty = .greenhorn,
         names: [String] = ["Sierra", "Anna", "Jed", "Zeke", "Mary"], departureMonth: Int = 4, seed: UInt32, edition: GameEdition = .macintosh11) {
        self.edition = edition
        self.profession = profession
        self.difficulty = difficulty
        self.departureMonth = min(8, max(3, departureMonth))
        cash = profession.startingCash
        randomState = seed
        original = OriginalJourneyState()
        inventoryUnitsVersion = 1
        let safeNames = names.isEmpty ? ["Traveler"] : Array(names.prefix(5))
        members = safeNames.enumerated().map { i, name in
            // CODE19 commits accepted Mac Roman fields without trimming or case changes.
            // Only the nonthrowing programmatic initializer's invalid inputs retain
            // the old normalization fallback; UI registration validates first.
            if OriginalRegistration.isValidName(name) { return PartyMember(id: i, name: name) }
            let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
            return PartyMember(id: i, name: trimmed.isEmpty ? "Traveler \(i + 1)" : trimmed)
        }
    }

    var damagedParts: [Supply] {
        let stored = (brokenPart.map { [$0] } ?? []) + (additionalBrokenParts ?? [])
        return [.wheels, .axles, .tongues].filter { stored.contains($0) }
    }

    mutating func markBroken(_ part: Supply) {
        var parts = damagedParts
        if !parts.contains(part) { parts.append(part) }
        brokenPart = parts.first
        additionalBrokenParts = Array(parts.dropFirst())
    }

    mutating func clearBroken(_ part: Supply) {
        let parts = damagedParts.filter { $0 != part }
        brokenPart = parts.first
        additionalBrokenParts = Array(parts.dropFirst())
    }

    var livingMembers: [PartyMember] { members.filter(\.alive) }
    var location: TrailStop { TrailCatalog.stop(locationID) }
    var destination: TrailStop? { destinationID.map(TrailCatalog.stop) }
    var milesToNext: Int { max(0, legDistance - legProgress) }
    // Legacy percentages remain only for compatibility with old saves and callers.
    // New daily simulation and scoring use the shared original badness byte.
    var healthBadness: UInt8 {
        if let original { return original.badness }
        let average = livingMembers.isEmpty ? 0 : livingMembers.map(\.health).reduce(0, +) / Double(livingMembers.count)
        return average >= 70 ? 0 : average >= 45 ? 35 : average >= 20 ? 70 : 105
    }
    var averageHealth: Double { livingMembers.isEmpty ? 0 : [100.0, 60, 35, 10][min(3, Int(healthBadness) / 35)] }
    var healthLabel: String { ["Good", "Fair", "Poor", "Very Poor"][min(3, Int(healthBadness) / 35)] }
    var originalWeatherCategory: Int { Int(original?.weather.category ?? 0) & 127 }
    var originalTemperatureCategory: Int { Int(original?.weather.temperature ?? 2) }

    /// CODE7:0x0c32–0x0c3e renders (rawOxen+1)/2; all other quantities retain
    /// their existing units. Store purchase inputs convert pairs to raw oxen.
    func displayQuantity(_ supply: Supply) -> Int {
        if supply == .oxen && inventoryUnitsVersion == 1 { return (inventory[supply] + 1) / 2 }
        return inventory[supply]
    }

    mutating func ensureOriginalState() {
        if inventoryUnitsVersion == nil {
            inventory[.oxen] *= 2
            if inventory[.oxen] > Supply.oxen.capacity { legacyOxenLimit = inventory[.oxen] }
            inventoryUnitsVersion = 1
        }
        guard original == nil else { return }
        // Migration is deliberately approximate: old saves did not store original
        // badness, accumulator values, or climate. Preserve their health band.
        var migrated = OriginalJourneyState()
        migrated.badness = healthBadness
        switch weather {
        case .sunny: migrated.weather.category = 0
        case .hot: migrated.weather.category = 0; migrated.weather.temperature = 5
        case .cold: migrated.weather.category = 2; migrated.weather.temperature = 1
        case .rain: migrated.weather.category = 3; migrated.weather.rainIncrement = 20
        case .snow: migrated.weather.category = 5; migrated.weather.temperature = 1; migrated.weather.snowIncrement = 160
        case .storm: migrated.weather.category = 7; migrated.weather.rainIncrement = 100
        }
        migrated.weather.initialized = true
        migrated.flags = phase == .travel ? 2 : 0
        if delayDays > 0 { migrated.flags |= 8 }
        original = migrated
        // Two legacy South Pass distances were reversed. Keep distance already
        // traveled, but normalize the active leg to the verified destination.
        if phase == .travel, locationID == "south-pass",
           (destinationID == "bridger" && legDistance == 125) || (destinationID == "green" && legDistance == 57),
           let leg = location.routes.first(where: { $0.destination == destinationID }) {
            legDistance = leg.miles
            legProgress = min(legProgress, leg.miles)
        }
    }

    mutating func synchronizeSharedHealth() {
        let displayHealth = averageHealth
        for i in members.indices where members[i].alive { members[i].health = displayHealth }
    }
    var originalDate: OriginalCalendar.Components { OriginalCalendar.date(departureMonth: departureMonth, daysElapsed: daysElapsed) }
    var dateText: String { originalDate.text }
    var month: Int { originalDate.month }
    var canShop: Bool { phase == .outfitting || (phase == .landmark && location.store) }
    var canCamp: Bool { originalRiverOutcome == nil && originalTradeSession == nil && [.travel, .landmark, .river, .fork].contains(phase) }
    /// CODE6 checks the raw weather byte, then zero remaining miles, then ammunition.
    /// Lifecycle/live-party guards remain separate from original rejection messages.
    var huntEligibility: OriginalHuntEligibility.Decision {
        OriginalHuntEligibility.evaluate(weatherCategory: original?.weather.category ?? 0,
            milesRemaining: UInt8(clamping: phase == .travel ? milesToNext : 0),
            ammunition: Int16(clamping: inventory[.bullets]))
    }
    var canHunt: Bool { canCamp && !livingMembers.isEmpty && huntEligibility == .allowed }
    var canSave: Bool { phase != .hunting && phase != .rafting }

    mutating func record(_ text: String, originalEvent: Int? = nil) {
        let face = originalEvent.map { OriginalSaveJournal.usesBoldFace(opcode: $0, actorWagonSlot: 0, localWagonSlot: 0) }
        journal.append(JournalEntry(id: (journal.last?.id ?? -1) + 1, day: daysElapsed,
                                   text: OriginalJournalRules.finishSentence(text), originalBold: face))
        if journal.count > 500 { journal.removeFirst(journal.count - 500) }
    }

    // Original CODE1:0x073e wrapper; the QuickDraw seed is part of the save.
    mutating func roll(_ upper: Int) -> Int {
        precondition(upper > 0)
        var random = OriginalRandom(seed: randomState)
        let result = random.bounded(upper)
        randomState = random.seed
        return result
    }

}

struct GameRuleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func dollars(_ cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.usesGroupingSeparator = true
    return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
}
