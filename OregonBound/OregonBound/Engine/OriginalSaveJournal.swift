import Foundation

/// CODE14:1ae8–1bf8 compact journal record boundaries. Raw padding and opaque
/// fields survive round trips. Input must be the used range, not buffer padding.
struct OriginalSaveJournal: Equatable, Sendable {
    enum DecodeError: Error, Equatable {
        case truncated(offset: Int, requiredEnd: Int, available: Int)
        case unsupportedOpcode(UInt8, offset: Int)
    }
    struct DateMarker: Equatable, Sendable {
        let year: UInt16
        let month: UInt8
        let day: UInt8
    }
    struct Supplies: Equatable, Sendable {
        let rawOxen: UInt8
        let clothing: UInt8
        let wheels: UInt8
        let axles: UInt8
        let tongues: UInt8
        let ammunition: Int16
        let food: Int16
        let cashCents: Int32
    }
    /// CODE14:28a0: the low item/quantity is received by the requester;
    /// the high item/quantity is given by the requester. Oxen are whole animals.
    struct Trade: Equatable, Sendable {
        let counterpartyByte: UInt8
        let requesterByte: UInt8
        let receivedItem: UInt8
        let givenItem: UInt8
        let receivedQuantity: Int32
        let givenQuantity: Int32
    }
    enum Decision: Equatable, Sendable {
        case huntReturn(food: UInt8)
        case action(code: UInt8, parameter: UInt8)
        case unableToContinue(packedWagon: UInt8, reasonStringIndex: UInt8)
        case travelingAlone
    }
    struct Speech: Equatable, Sendable {
        let messageBytes: Data
        /// Nil means broadcast (119);118 contains a length-prefixed list of IDs.
        let recipientWagonSlots: [UInt8]?
        var message: String { String(data: messageBytes, encoding: .macOSRoman)! }
    }
    struct Record: Equatable, Sendable {
        let offset: Int
        let rawBytes: Data
        fileprivate init(offset: Int, rawBytes: Data) {
            self.offset = offset
            self.rawBytes = rawBytes
        }
        var opcode: UInt8 { rawBytes[0] }
        /// Meaning depends on opcode; do not interpret date/weather bytes as actors.
        var parameterByte: UInt8 { rawBytes[1] }
        var wagonSlotBits: Int { Int(parameterByte & 31) }
        var highParameterBits: Int { Int(parameterByte >> 5) }
        var date: DateMarker? {
            guard opcode == 120 else { return nil }
            return DateMarker(year: word(2), month: rawBytes[4], day: rawBytes[5])
        }
        var supplies: Supplies? {
            guard (63...69).contains(opcode) else { return nil }
            return Supplies(rawOxen: rawBytes[2], clothing: rawBytes[3], wheels: rawBytes[4],
                axles: rawBytes[5], tongues: rawBytes[14], ammunition: Int16(bitPattern: word(6)),
                food: Int16(bitPattern: word(8)), cashCents: Int32(bitPattern: UInt32(word(10)) << 16 | UInt32(word(12))))
        }
        var trade: Trade? {
            guard (70...84).contains(opcode) else { return nil }
            return Trade(counterpartyByte: rawBytes[1], requesterByte: rawBytes[2],
                receivedItem: rawBytes[3] & 15, givenItem: rawBytes[3] >> 4,
                receivedQuantity: long(4), givenQuantity: long(8))
        }
        var decision: Decision? {
            switch opcode {
            case 105: return .huntReturn(food: rawBytes[2])
            case 106...109: return .action(code: rawBytes[1], parameter: rawBytes[2])
            case 110: return .unableToContinue(packedWagon: rawBytes[1], reasonStringIndex: rawBytes[2])
            case 111: return .travelingAlone
            default: return nil
            }
        }
        private func long(_ offset: Int) -> Int32 {
            Int32(bitPattern: UInt32(word(offset)) << 16 | UInt32(word(offset + 2)))
        }
        var speech: Speech? {
            guard opcode == 118 || opcode == 119 else { return nil }
            let messageEnd = 3 + Int(rawBytes[2])
            let recipients: [UInt8]? = opcode == 118
                ? Array(rawBytes[(messageEnd + 1)..<(messageEnd + 1 + Int(rawBytes[messageEnd]))]) : nil
            return Speech(messageBytes: Data(rawBytes[3..<messageEnd]), recipientWagonSlots: recipients)
        }
        private func word(_ offset: Int) -> UInt16 {
            UInt16(rawBytes[offset]) << 8 | UInt16(rawBytes[offset + 1])
        }
    }
    let records: [Record]
    var data: Data { records.reduce(into: Data()) { $0.append($1.rawBytes) } }

    init(usedBytes: Data) throws {
        let bytes = Array(usedBytes)
        var offset = 0
        var records: [Record] = []
        func require(_ end: Int) throws {
            guard end <= bytes.count else { throw DecodeError.truncated(offset: offset, requiredEnd: end, available: bytes.count) }
        }
        while offset < bytes.count {
            let opcode = bytes[offset]
            var end: Int
            switch opcode {
            case 0...62: end = offset + 2
            case 63...69: end = offset + 16
            case 70...84: end = offset + 12
            case 85...95, 105...111: end = offset + 4
            case 120: end = offset + 6
            case 118, 119:
                try require(offset + 3)
                end = offset + 3 + Int(bytes[offset + 2])
                try require(end)
                if opcode == 118 {
                    try require(end + 1)
                    end += 1 + Int(bytes[end])
                }
                // Final word alignment is relative to record start, not host address.
                if (end - offset) & 1 != 0 { end += 1 }
            default: throw DecodeError.unsupportedOpcode(opcode, offset: offset)
            }
            try require(end)
            records.append(Record(offset: offset, rawBytes: Data(bytes[offset..<end])))
            offset = end
        }
        self.records = records
    }

    struct Presentation: Equatable, Sendable {
        /// Nil explicitly means this opcode's full original text is not recovered.
        let text: String?
        let unresolvedReason: String?
    }

    /// Bounded, verified visible text for dates and common single-wagon events.
    /// The caller supplies original STR# strings and unmodified registered names.
    /// Row visibility and multiplayer world-state decisions are separate from text.
    static func presentation(of record: Record, localWagonSlot: Int,
                             strings: (Int, Int) -> String?,
                             memberName: (Int, Int) -> String?) -> Presentation {
        func unresolved(_ reason: String) -> Presentation { Presentation(text: nil, unresolvedReason: reason) }
        func finished(_ text: String) -> Presentation {
            // Includes the original 255-byte limit for adding final punctuation.
            Presentation(text: OriginalJournalRules.finishSentence(text), unresolvedReason: nil)
        }
        let opcode = Int(record.opcode)
        if let date = record.date {
            guard let month = strings(3014, Int(date.month)) else { return unresolved("Missing original month string") }
            return finished("• \(month) \(date.day), \(Int(Int16(bitPattern: date.year))) •")
        }
        if opcode <= 19 {
            guard let text = strings(1501, opcode + 1) else { return unresolved("Missing original STR#1501 item") }
            return finished(text)
        }
        func resolved(_ template: String, _ values: [String: String]) -> Presentation {
            var text = template
            for (key, value) in values { text = text.replacingOccurrences(of: key, with: value) }
            guard !(0...9).contains(where: { text.contains("^\($0)") }) else {
                return unresolved("Original template still requires substitutions")
            }
            return finished(text)
        }
        func actor(_ byte: UInt8, capitalized: Bool) -> String? {
            if Int(byte & 31) == localWagonSlot {
                guard let you = strings(1500, 2) else { return nil }
                guard !capitalized, var bytes = you.data(using: .macOSRoman), !bytes.isEmpty else { return you }
                if (65...90).contains(bytes[0]) { bytes[0] += 32 }
                return String(data: bytes, encoding: .macOSRoman)
            }
            return memberName(Int(byte & 31), 0)
        }
        if (63...68).contains(opcode), let supplies = record.supplies {
            guard record.wagonSlotBits == localWagonSlot else { return unresolved("Other-wagon supply sentence not ported") }
            let list = OriginalJournalRules.supplyList(rawQuantities: [Int(supplies.rawOxen), Int(supplies.clothing),
                Int(supplies.ammunition), Int(supplies.wheels), Int(supplies.axles), Int(supplies.tongues), Int(supplies.food)],
                cashCents: Int(supplies.cashCents))
            let resource = list.isEmpty && (opcode == 63 || opcode == 66) ? 1523 : 1503
            guard let template = strings(resource, opcode - 62) else { return unresolved("Missing original supply template") }
            return resolved(template, ["^2": list])
        }
        if let trade = record.trade {
            // Both original trade tables end at item11. Reserved81...84 have no authored text.
            guard opcode <= 80 else { return unresolved("Reserved trade opcode has no authored STR#1505/1525 item") }
            let requesterIsLocal = Int(trade.requesterByte) == localWagonSlot
            let counterpartyIsLocal = Int(trade.counterpartyByte) == localWagonSlot
            if !requesterIsLocal && !counterpartyIsLocal && opcode == 72 {
                guard let template = strings(1505, 11),
                      let first = memberName(Int(trade.counterpartyByte), 0),
                      let second = memberName(Int(trade.requesterByte), 0) else { return unresolved("Missing trade observer names/template") }
                // A5−1e18 is ^0; A5−1e14 is ^3.
                return resolved(template, ["^0": first, "^3": second])
            }
            guard let template = strings(requesterIsLocal ? 1505 : 1525, opcode - 69) else {
                return unresolved("Missing original trade template")
            }
            func quantity(item: UInt8, amount: Int32) -> String? {
                guard amount >= 0, item <= 8 else { return nil }
                if amount == 0 { return "" } // Zero check precedes the item8/nothing branch.
                if item == 8 { return strings(3011, 15) }
                if item == 7 {
                    return "$" + OriginalJournalRules.number(Int(amount) / 100) + String(format: ".%02d", Int(amount) % 100)
                }
                guard let noun = strings(3011, Int(item) + (amount == 1 ? 8 : 1)) else { return nil }
                return OriginalJournalRules.number(Int(amount)) + " " + noun
            }
            guard let received = quantity(item: trade.receivedItem, amount: trade.receivedQuantity) else {
                return unresolved("Negative trade quantity or unsupported item")
            }
            var values = ["^2": received]
            if opcode >= 72 {
                guard let given = quantity(item: trade.givenItem, amount: trade.givenQuantity) else {
                    return unresolved("Negative trade quantity or unsupported item")
                }
                values["^4"] = given
            }
            if template.contains("^6") {
                guard let name = actor(requesterIsLocal ? trade.counterpartyByte : trade.requesterByte, capitalized: true) else {
                    return unresolved("Missing original trade counterparty name")
                }
                values["^6"] = name
            }
            return resolved(template, values)
        }
        if let decision = record.decision {
            guard var text = strings(1507, opcode - 104) else { return unresolved("Missing original decision template") }
            switch decision {
            case .huntReturn(let food): return resolved(text, ["^5": String(food)])
            case .travelingAlone:
                guard let alone = strings(1507, 24) else { return unresolved("Missing traveling-alone template") }
                return finished(alone)
            case .unableToContinue(let wagon, let reason):
                guard let you = strings(1500, 2), let name = actor(wagon, capitalized: false),
                      let suffix = strings(Int(wagon & 31) == localWagonSlot ? 3020 : 3019, Int(reason)) else {
                    return unresolved("Missing original continuation reason or wagon name")
                }
                // Single-wagon world+8 ==1 branch. Multiplayer subject differs.
                return resolved(text + suffix, ["^0": you, "^6": name])
            case .action(let code, let parameter):
                let suffixIndex: Int
                var values: [String: String] = [:]
                switch code {
                case 1: suffixIndex = 7
                case 2: suffixIndex = 8
                case 3: suffixIndex = 15
                case 4:
                    suffixIndex = parameter == 1 ? 16 : 17
                    values["^5"] = String(parameter)
                case 5:
                    suffixIndex = 18
                    guard let pace = strings(3009, Int(parameter) + 1), let bytes = pace.data(using: .macOSRoman) else {
                        return unresolved("Missing original pace string")
                    }
                    values["^5"] = String(data: Data(bytes.map { (65...90).contains($0) ? $0 + 32 : $0 }), encoding: .macOSRoman)!
                case 6: suffixIndex = 20
                case 7:
                    suffixIndex = 21
                    guard let name = memberName(Int(parameter), 0) else { return unresolved("Missing elected captain name") }
                    values["^6"] = name
                case 8:
                    suffixIndex = 22
                    guard let form = strings(1500, parameter == 255 ? 9 : 10) else { return unresolved("Missing government string") }
                    values["^5"] = form
                case 9:
                    suffixIndex = 23
                    guard let name = actor(parameter, capitalized: false) else { return unresolved("Missing left-behind wagon name") }
                    values["^6"] = name
                case 10: suffixIndex = 19
                case 17: suffixIndex = 26
                case 66:
                    guard let name = strings(3002, Int(parameter) + 1),
                          let prefix = parameter < 17 ? strings(1507, 9) : "" else { return unresolved("Missing original trail string") }
                    return resolved(text + prefix + name, [:])
                case 130:
                    guard let crossing = strings(1507, 10), let method = strings(1507, Int(parameter >> 5) + 11) else {
                        return unresolved("Missing original river method string")
                    }
                    // The original replaces the entire vote/decision prefix here.
                    return resolved(crossing, ["^5": method])
                default: return unresolved("Unrecognized original decision action \(code)")
                }
                guard let suffix = strings(1507, suffixIndex) else { return unresolved("Missing original action suffix") }
                text += suffix
                return resolved(text, values)
            }
        }
        var resource = 1502, item = opcode - 19
        var replacements: [String: String] = [:]
        switch opcode {
        case 20, 25: break
        case 21...24, 35:
            guard record.wagonSlotBits == localWagonSlot else { return unresolved("Other-wagon sentence not yet ported") }
        case 26...29, 36...42, 52, 54...59:
            guard record.wagonSlotBits == localWagonSlot,
                  let name = memberName(record.wagonSlotBits, record.highParameterBits) else {
                return unresolved("Unavailable original member name or other-wagon sentence")
            }
            replacements["^0"] = name
        case 30...34:
            guard record.wagonSlotBits == localWagonSlot,
                  let part = strings(3011, record.highParameterBits + 8) else { return unresolved("Unavailable original spare-part string") }
            replacements["^2"] = part
        case 43:
            guard let ration = strings(3010, record.highParameterBits + 1), let bytes = ration.data(using: .macOSRoman) else {
                return unresolved("Unavailable original ration string")
            }
            let lower = bytes.map { (65...90).contains($0) ? $0 + 32 : $0 }
            replacements["^5"] = String(data: Data(lower), encoding: .macOSRoman)!
        case 44:
            guard record.wagonSlotBits == localWagonSlot else { return unresolved("Other-wagon death sentence not yet ported") }
            resource = 1522
        case 45:
            item = 27 // Single-wagon branch CODE14:20c8–20e2.
            guard let destination = strings(3002, Int(record.parameterByte) + 1) else { return unresolved("Missing original landmark string") }
            replacements["^5"] = destination
        default: return unresolved("Opcode \(opcode) text expansion is not yet ported")
        }
        guard var text = strings(resource, item) else { return unresolved("Missing original STR#\(resource) item\(item)") }
        for (key, value) in replacements { text = text.replacingOccurrences(of: key, with: value) }
        if (0...9).contains(where: { text.contains("^\($0)") }) { return unresolved("Original template still requires substitutions") }
        return finished(text)
    }
}
