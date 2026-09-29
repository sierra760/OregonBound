import Foundation

/// CODE14 journal string construction. Scoped to the current single wagon.
/// Original record strings are MacRoman Pascal strings, at most255 bytes.
enum OriginalJournalRules {
    enum Action {
        case timeOut, continueJourney, hunt, rest(UInt8), pace(Int), quit, exit
        case trail(name: String, originalIndex: UInt8), crossing(Int)
    }

    /// CODE14:1890–18b6 tests A≤last<z, not an alphabetic-character predicate.
    static func finishSentence(_ value: String) -> String {
        guard let bytes = value.data(using: .macOSRoman), bytes.count < 255,
              let last = bytes.last, last >= 0x41, last < 0x7a else { return value }
        return value + "."
    }

    /// CODE1:0a52–0ace inserts commas every3 digits. Positive supply counts only.
    static func number(_ value: Int) -> String {
        precondition(value >= 0)
        let source = String(value)
        var result = ""
        for (index, character) in source.enumerated() {
            if index > 0 && (source.count-index) % 3 == 0 && character != "-" { result += "," }
            result.append(character)
        }
        return result
    }

    /// Input uses raw inventory units. CODE16:283e packs byte/word journal fields;
    /// CODE14:25b6–2694 omits nonpositive signed words/cash, then formats in order.
    static func supplyList(rawQuantities: [Int], cashCents: Int = 0) -> String {
        precondition(rawQuantities.count == 7)
        let bytes = Set([0,1,3,4,5])
        let quantities = rawQuantities.enumerated().map { index, value in
            bytes.contains(index) ? Int(UInt8(truncatingIfNeeded: value)) : Int(Int16(truncatingIfNeeded: value))
        }
        var parts: [String] = []
        for (index, raw) in quantities.enumerated() where raw > 0 {
            let count = index == 0 ? (raw+1)/2 : raw
            let noun = string(3011,count == 1 ? index+8 : index+1)
            parts.append(number(count) + " " + noun)
        }
        let cents = Int(Int32(truncatingIfNeeded: cashCents))
        if cents > 0 {
            let fraction = String(cents % 100)
            parts.append("$" + number(cents/100) + "." + (fraction.count == 1 ? "0" : "") + fraction)
        }
        // CODE14:1d38 locates the last comma;26d0 inserts STR1500[5] after it.
        // This retains a comma even when the list has only two entries.
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
    }

    static func supplyEvent(id: Int, rawQuantities: [Int], cashCents: Int = 0) -> String? {
        guard (63...68).contains(id) else { return nil }
        let supplies = supplyList(rawQuantities: rawQuantities,cashCents: cashCents)
        // CODE14:26ec–2746 selects the no-supplies form only for63 and66.
        let template = supplies.isEmpty && (id == 63 || id == 66)
            ? string(1523,id-62) : string(1503,id-62)
        return finishSentence(template.replacingOccurrences(of: "^2",with: supplies))
    }

    static func weatherEvent(_ id: Int) -> String? {
        guard (0...12).contains(id) else { return nil }
        return finishSentence(string(1501,id+1))
    }

    /// A template accessor, not a full multiplayer/member-reference interpreter.
    /// Caller replaces ^0/^2/^5/^6 before calling finishSentence.
    static func currentWagonTemplate(event: Int) -> String? {
        guard (20...62).contains(event) else { return nil }
        if event == 44 { return string(1522,25) } // CODE14:2078 current wagon.
        if event == 45 { return string(1502,27) } // CODE14:20d8 single wagon.
        return string(1502,event-19)
    }

    static func rations(_ index: Int) -> String {
        finishSentence(string(1502,24).replacingOccurrences(of: "^5",with: lowercaseASCII(string(3010,index+1))))
    }

    /// CODE14:1e96–1f46 uses the currently selected wagon's possessive "your".
    static func drownedMembers(_ count: Int) -> String {
        finishSentence(string(1502,34)
            .replacingOccurrences(of: "^7",with: String(count))
            .replacingOccurrences(of: "^5",with: count > 1 ? "s " : " ")
            .replacingOccurrences(of: "^6",with: "your"))
    }

    /// CODE14:2aa6–2ace uses the food byte and short journal STR1507[1].
    static func huntReturn(food: Int) -> String {
        finishSentence(string(1507,1).replacingOccurrences(of: "^5",with: String(UInt8(truncatingIfNeeded: food))))
    }

    /// CODE14:2a70/2baa, event109 selects "You decided to ". Crossing replaces it.
    static func decision(_ action: Action) -> String {
        let suffix: String
        switch action {
        case .timeOut: suffix = string(1507,7)
        case .continueJourney: suffix = string(1507,8)
        case .hunt: suffix = string(1507,15)
        case .rest(let days):
            suffix = days == 1 ? string(1507,16) : string(1507,17).replacingOccurrences(of: "^5",with: String(days))
        case .pace(let index):
            suffix = string(1507,18).replacingOccurrences(of: "^5",with: lowercaseASCII(string(3009,index+1)))
        case .quit: suffix = string(1507,19)
        case .exit: suffix = string(1507,20)
        case .trail(let name,let index): suffix = (index < 17 ? string(1507,9) : "") + name
        case .crossing(let method):
            return finishSentence(string(1507,10).replacingOccurrences(of: "^5",with: string(1507,method+10)))
        }
        return finishSentence(string(1507,5) + suffix)
    }

    /// CODE14:085a changes ASCII A...Z only, leaving MacRoman accented letters.
    private static func lowercaseASCII(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map {
            (65...90).contains($0.value) ? UnicodeScalar($0.value+32)! : $0
        }))
    }
    private static func string(_ resource: Int,_ index: Int) -> String {
        guard let table = tables[resource], table.indices.contains(index-1) else { return "" }
        return table[index-1]
    }

    // Extracted STR# resources, one-based lookup. Binary/resource tests verify text.
    private static let tables: [Int:[String]] = [
        1500: [
            "A person in ^0’s wagon",
            "You",
            "^6’s wagon",
            " really",
            " and",
            "one ",
            " ",
            ", ",
            "council",
            "captain",
            "Good luck traveling the trail alone.  It can be tough when you don’t have others to help you",
            "The wagon train",
        ],
        1501: [
            "Heavy fog",
            "Hailstorm",
            "You’ve lost the trail",
            "You took the wrong trail",
            "Rough trail",
            "The trail is impassable",
            "Heavy snow has rendered the wagon train snowbound",
            "Blizzard",
            "Severe storm",
            "No grass for the oxen",
            "No water",
            "Bad water",
            "Heavy snow has rendered your wagon snowbound",
        ],
        1502: [
            "An Indian helped you find some food",
            "An ox wandered off",
            "A farmer helped you with a sick ox",
            "An ox is sick",
            "An ox died",
            "You found some wild fruit",
            "^0 has a broken arm",
            "^0 has a broken leg",
            "^0 got lost",
            "^0 was bitten by a snake",
            "You had a ^2 break but were able to fix it",
            "A carpenter helped you fix your broken ^2",
            "A blacksmith helped you fix your broken ^2",
            "You had a ^2 break but were able to replace it from supplies",
            "You have a broken ^2 and are unable to fix it.  You will have to trade for one",
            "You have no more oxen.  You can't continue until you trade for one or more",
            "^0 is well again",
            "^0 is suffering from exhaustion",
            "^0 is sick with typhoid fever",
            "^0 has cholera",
            "^0 has the measles",
            "^0 has dysentery",
            "^0 has a fever",
            "You changed your rations to ^5",
            "Everyone in ^6’s wagon has died",
            "The wagon train has reached ^5",
            "You have reached ^5",
            "",
            "Your wagon train starts off with ^5 wagons and is being led by Captain ^6.",
            "^6 chose to leave the wagon train",
            "The wagon train resumed with ^5 wagons led by Captain ^6.",
            "^6's wagon has vanished.",
            "^0 was near death but the doctor was able to help",
            "^7 member^5of ^6 wagon drowned",
            "^0 got sick and died",
            "^0 died of snakebite",
            "^0 died of typhoid",
            "^0 died of cholera",
            "^0 died of measles",
            "^0 died of dysentery",
            "",
            "You resumed an Oregon Trail journey",
            "You resumed a Wagon Train 1848 journey",
        ],
        1522: [
            "",
            "^6 had an ox wander off",
            "A farmer helped ^6 with a sick ox",
            "^6 has a sick ox",
            "^6 had an ox die",
            "",
            "",
            "",
            "",
            "",
            "^6 had a ^2 break but was able to fix it",
            "A carpenter helped ^6 fix a broken ^2",
            "A blacksmith helped ^6 fix a broken ^2",
            "^6 had a ^2 break but was able to replace it from supplies",
            "^6 was unable to fix a broken ^2. They can’t continue until they trade for a new one",
            "^6 doesn’t have any oxen. They can’t continue until they trade for a new one",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "Everyone in your wagon has died.",
            "",
            "",
            "",
            "Your wagon train starts off with ^5 wagons led by a council government",
            "",
            "The wagon train resumed with ^5 wagons led by a council government",
            "RMSGSTR2 + ALTSTRING #32 vanished",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "You resumed your journey",
            "",
            "",
        ],
        1503: [
            "You found ^2 in an abandoned wagon",
            "A thief stole ^2 from your wagon",
            "A fire in your wagon destroyed ^2.",
            "Your wagon tipped and you lost ^2.",
            "You bought ^2 at the store",
            "You started down the trail with ^2.",
        ],
        1523: [
            "You found an abandoned wagon, but there were no supplies to be scavenged",
            "",
            "^6’s wagon was damaged by fire",
            "Your wagon tipped but you lost nothing",
        ],
        1507: [
            "You brought back ^5 pounds of food from hunting",
            "The wagon train voted to ",
            "The wagon train voted not to ",
            "The captain decided to ",
            "You decided to ",
            "^0 can’t continue because ^6 ",
            "call a time out",
            "continue",
            "take the trail to ",
            "You chose to ^5 the river",
            "ford",
            "caulk your wagon and float it across",
            "take a ferry across",
            "have an Indian guide help you cross",
            "hunt",
            "rest for one day",
            "rest for ^5 days",
            "change the pace to ^5",
            "quit the game",
            "exit the game",
            "elect ^6 as the new captain",
            "change to a ^5 form of government",
            "leave ^6 behind",
            "You are now traveling alone",
            "",
            "hold a conference",
        ],
        3009: [
            "Steady",
            "Strenuous",
            "Grueling",
            "Resting",
            "Delayed",
            "Hunting",
            "In the store",
            "Voting",
            "Moving",
            "Stopped",
            "Crossing River",
            "Conference",
            "Trading",
        ],
        3010: [
            "Filling",
            "Meager",
            "Bare Bones",
        ],
        3011: [
            "oxen",
            "sets of clothing",
            "bullets",
            "wagon wheels",
            "wagon axles",
            "wagon tongues",
            "pounds of food",
            "ox",
            "set of clothing",
            "bullet",
            "wagon wheel",
            "wagon axle",
            "wagon tongue",
            "pound of food",
            "nothing",
            "more ",
        ],
    ]
}
