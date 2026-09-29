import Foundation

/// CODE19:0a16–0ad4 registration commit. Validation counts original Mac Roman
/// bytes, preserves whitespace/case, and compacts valid companion fields.
enum OriginalRegistration {
    static func partyNames(pool: [String], random: (Int) -> Int) -> [String] {
        precondition(pool.count == 10)
        var order = Array(0..<10)
        for index in 0..<10 { order.swapAt(index, random(10)) }
        return [""] + (1...4).map { pool[order[$0]] }
    }

    enum ValidationError: Error, Equatable {
        case invalidLeader
        case tooManyCompanionFields
    }
    static func isValidName(_ name: String) -> Bool {
        guard let bytes = name.data(using: .macOSRoman) else { return false }
        return (1...15).contains(bytes.count)
    }
    /// The original has four companion fields. Blank, overlong or unencodable
    /// companion fields are omitted; an invalid leader prevents commitment.
    static func commitNames(leader: String, companions: [String]) throws -> [String] {
        guard isValidName(leader) else { throw ValidationError.invalidLeader }
        guard companions.count <= 4 else { throw ValidationError.tooManyCompanionFields }
        return [leader] + companions.filter(isValidName)
    }
}
