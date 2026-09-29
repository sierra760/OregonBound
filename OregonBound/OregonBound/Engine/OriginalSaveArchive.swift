import Foundation

/// Lossless CODE6 save-data fork. Unknown fields, inactive wagons, journal
/// bookkeeping pointers and unused buffer bytes remain opaque and unchanged.
/// This is not a Journey importer or a constructor for a new original game.
struct OriginalSaveArchive: Equatable, Sendable {
    static let byteCount = 0x3868
    static let headerSize = 0x28
    static let worldOffset = 0x28
    static let worldSize = 0x101e
    static let journalStateOffset = 0x1046
    static let journalStateSize = 0x22
    static let journalOffset = 0x1068
    static let journalSize = 0x2800
    static let playerOffset = 0x25e
    static let playerSize = 0x6e
    static let playerCapacity = 32
    static let finderType: UInt32 = 0x4f524443 // ORDC
    static let finderCreator: UInt32 = 0x4f52474e // ORGN

    enum ArchiveError: Error, Equatable {
        case truncated(actual: Int, minimum: Int)
        case unsupportedVersion(UInt16)
        case invalidBlockLength(expected: Int, actual: Int)
        case invalidPlayerIndex(Int)
        case unsupportedWagonSlotCount(Int)
        case invalidWagonSlotCount(Int)
        case missingSingleWagon
        case invalidMemberSlot(Int)
        case invalidWagonSlot(Int)
        case invalidNameLength(Int)
        case unencodableName
    }

    /// Raw bytes; categorical values are deliberately not converted to native enums.
    enum WorldByteField: Int, CaseIterable, Sendable {
        case month = 0x02, day = 0x03, pace = 0x04, flags = 0x05
        case delayDays = 0x06, restDays = 0x07
        case climateRow = 0x22c, weatherCategory = 0x22d, temperatureCategory = 0x22e
        case destinationRaw = 0x238, remainingMiles = 0x239
        case legLength = 0x23c, lastMovement = 0x23d, routeFlags = 0x23e
        case wagonSlotCount = 0x240, departureMonth = 0x241, departureDay = 0x242
        case simulationSpeed = 0x243, huntTime = 0x247
    }
    enum WorldWordField: Int, CaseIterable, Sendable {
        case year = 0, rainAccumulator = 0x230, snowAccumulator = 0x232
        case rainIncrement = 0x234, snowIncrement = 0x236, cumulativeMiles = 0x23a
    }
    enum PlayerByteField: Int, CaseIterable, Sendable {
        case flags = 0, secondaryFlags = 1, rations = 2, occupation = 3
        case survivors = 4, memberSlotCount = 5
        case healthBadness = 0x5e, auxiliaryHealth = 0x5f, pendingPenalty = 0x60
    }
    /// Values are raw UInt16 bit patterns; signed arithmetic and oxen display
    /// conversion belong to the original model, not to archive decoding.
    enum PlayerWordField: Int, CaseIterable, Sendable {
        case rawOxen = 0x46, clothing = 0x48, ammunition = 0x4a
        case spareWheels = 0x4c, spareAxles = 0x4e, spareTongues = 0x50, food = 0x52
    }

    enum PlayerLongField: Int, CaseIterable, Sendable { case cashCents = 0x54 }

    private var bytes: [UInt8]

    init(data: Data) throws {
        guard data.count >= Self.byteCount else {
            throw ArchiveError.truncated(actual: data.count, minimum: Self.byteCount)
        }
        bytes = Array(data)
        guard version == 2 else { throw ArchiveError.unsupportedVersion(version) }
        // CODE6:02b0 checks version only. The original reads two fixed-size
        // blocks and ignores a larger file tail; retain that tail losslessly.
    }

    var data: Data { Data(bytes) }
    var version: UInt16 { word(at: 4) }
    var hasCanonicalSignature: Bool { Array(bytes[0..<4]) == [0x4d, 0x45, 0x43, 0x43] }
    var headerBytes: Data { Data(bytes[0..<Self.headerSize]) }
    var labelStorageBytes: Data { Data(bytes[6..<38]) }
    var label: String? {
        let count = Int(bytes[6])
        guard count <= 31 else { return nil }
        return String(data: Data(bytes[7..<(7 + count)]), encoding: .macOSRoman)
    }
    /// The value copied from A5−278e. Its semantic role is not established.
    var headerWord38: UInt16 { word(at: 38) }
    var worldBytes: Data { Data(bytes[Self.worldOffset..<Self.journalStateOffset]) }
    var journalStateBytes: Data { Data(bytes[Self.journalStateOffset..<Self.journalOffset]) }
    var journalBytes: Data { Data(bytes[Self.journalOffset..<Self.byteCount]) }
    var trailingBytes: Data { Data(bytes[Self.byteCount...]) }

    func worldByte(_ field: WorldByteField) -> UInt8 { bytes[Self.worldOffset + field.rawValue] }
    func worldWord(_ field: WorldWordField) -> UInt16 { word(at: Self.worldOffset + field.rawValue) }
    mutating func setWorldByte(_ field: WorldByteField, _ value: UInt8) {
        bytes[Self.worldOffset + field.rawValue] = value
    }
    mutating func setWorldWord(_ field: WorldWordField, _ value: UInt16) {
        setWord(at: Self.worldOffset + field.rawValue, value)
    }
    var destinationIndex: Int { Int(Int8(bitPattern: worldByte(.destinationRaw))) }

    func playerBytes(record: Int) throws -> Data {
        let offset = try playerAddress(record)
        return Data(bytes[offset..<(offset + Self.playerSize)])
    }
    func playerByte(_ field: PlayerByteField, record: Int) throws -> UInt8 {
        bytes[try playerAddress(record) + field.rawValue]
    }
    func playerWord(_ field: PlayerWordField, record: Int) throws -> UInt16 {
        word(at: try playerAddress(record) + field.rawValue)
    }
    mutating func setPlayerByte(_ field: PlayerByteField, _ value: UInt8, record: Int) throws {
        bytes[try playerAddress(record) + field.rawValue] = value
    }
    mutating func setPlayerWord(_ field: PlayerWordField, _ value: UInt16, record: Int) throws {
        setWord(at: try playerAddress(record) + field.rawValue, value)
    }
    func playerLong(_ field: PlayerLongField, record: Int) throws -> UInt32 {
        long(at: try playerAddress(record) + field.rawValue)
    }
    mutating func setPlayerLong(_ field: PlayerLongField, _ value: UInt32, record: Int) throws {
        let address = try playerAddress(record) + field.rawValue
        setWord(at: address, UInt16(value >> 16))
        setWord(at: address + 2, UInt16(truncatingIfNeeded: value))
    }

    /// Names are 16-byte Pascal slots. Leader storage is in the world header;
    /// companions 1...4 are in the wagon selected by the active-slot mapping.
    func memberName(memberSlot: Int, wagonSlot: Int) throws -> String {
        let address = try nameAddress(memberSlot: memberSlot, wagonSlot: wagonSlot)
        let count = Int(bytes[address])
        guard count <= 15 else { throw ArchiveError.invalidNameLength(count) }
        return String(data: Data(bytes[(address + 1)..<(address + 1 + count)]), encoding: .macOSRoman)!
    }
    mutating func setMemberName(_ name: String, memberSlot: Int, wagonSlot: Int) throws {
        let address = try nameAddress(memberSlot: memberSlot, wagonSlot: wagonSlot)
        guard let encoded = name.data(using: .macOSRoman) else { throw ArchiveError.unencodableName }
        guard encoded.count <= 15 else { throw ArchiveError.invalidNameLength(encoded.count) }
        bytes[address] = UInt8(encoded.count)
        bytes.replaceSubrange((address + 1)..<(address + 1 + encoded.count), with: encoded)
        // Original Pascal copy leaves unused bytes untouched.
    }
    private func nameAddress(memberSlot: Int, wagonSlot: Int) throws -> Int {
        guard (0..<5).contains(memberSlot) else { throw ArchiveError.invalidMemberSlot(memberSlot) }
        guard (0..<32).contains(wagonSlot) else { throw ArchiveError.invalidWagonSlot(wagonSlot) }
        if memberSlot == 0 { return Self.worldOffset + 0x2a + 16 * wagonSlot }
        let record = Int(bytes[Self.worldOffset + 0x0a + wagonSlot])
        return try playerAddress(record) + 6 + 16 * (memberSlot - 1)
    }

    func condition(memberSlot: Int, record: Int) throws -> UInt8 {
        guard (0..<5).contains(memberSlot) else { throw ArchiveError.invalidMemberSlot(memberSlot) }
        return bytes[try playerAddress(record) + 0x61 + memberSlot]
    }
    func conditionDays(memberSlot: Int, record: Int) throws -> UInt8 {
        guard (0..<5).contains(memberSlot) else { throw ArchiveError.invalidMemberSlot(memberSlot) }
        return bytes[try playerAddress(record) + 0x66 + memberSlot]
    }

    /// Single-wagon interpretation is explicit. The archive itself preserves
    /// all 32 records and can round-trip multiplayer bytes without simulating them.
    func singleWagonPlayerIndex() throws -> Int {
        let count = Int(worldByte(.wagonSlotCount))
        guard count == 1 else { throw ArchiveError.unsupportedWagonSlotCount(count) }
        let record = Int(bytes[Self.worldOffset + 0x0a])
        guard record != 255 else { throw ArchiveError.missingSingleWagon }
        _ = try playerAddress(record)
        return record
    }

    mutating func replaceWorldBytes(_ data: Data) throws {
        try replaceBlock(at: Self.worldOffset, count: Self.worldSize, data: data)
    }
    mutating func replaceJournalStateBytes(_ data: Data) throws {
        try replaceBlock(at: Self.journalStateOffset, count: Self.journalStateSize, data: data)
    }
    mutating func replaceJournalBytes(_ data: Data) throws {
        try replaceBlock(at: Self.journalOffset, count: Self.journalSize, data: data)
    }

    /// CODE14:0a14 preserves cursor-base when relocating process pointers.
    /// Invalid/out-of-buffer values remain intact but cannot be exposed as a slice.
    var journalUsedByteCount: Int? {
        let base = long(at: Self.journalStateOffset)
        let cursor = long(at: Self.journalStateOffset + 4)
        let count = cursor &- base
        return count <= UInt32(Self.journalSize) ? Int(count) : nil
    }
    var usedJournalBytes: Data? {
        journalUsedByteCount.map { Data(bytes[Self.journalOffset..<(Self.journalOffset + $0)]) }
    }

    /// Explicit optional transformation, separate from lossless decode:
    /// CODE6:02f4–0362 clears global flags then slot-indexed player flag pairs.
    /// It tests each mapping for FF but does not use the mapped record as the target.
    func applyingOriginalLoadFlagReset() throws -> Self {
        let count = Int(worldByte(.wagonSlotCount))
        guard count <= Self.playerCapacity else { throw ArchiveError.invalidWagonSlotCount(count) }
        var result = self
        result.setWorldByte(.flags, 0)
        for slot in 0..<count where bytes[Self.worldOffset + 0x0a + slot] != 255 {
            try result.setPlayerByte(.flags, 0, record: slot)
            try result.setPlayerByte(.secondaryFlags, 0, record: slot)
        }
        return result
    }

    private func playerAddress(_ record: Int) throws -> Int {
        guard (0..<Self.playerCapacity).contains(record) else { throw ArchiveError.invalidPlayerIndex(record) }
        return Self.worldOffset + Self.playerOffset + record * Self.playerSize
    }
    private func word(at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
    private func long(at offset: Int) -> UInt32 {
        UInt32(word(at: offset)) << 16 | UInt32(word(at: offset + 2))
    }
    private mutating func setWord(at offset: Int, _ value: UInt16) {
        bytes[offset] = UInt8(value >> 8)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
    }
    private mutating func replaceBlock(at offset: Int, count: Int, data: Data) throws {
        guard data.count == count else { throw ArchiveError.invalidBlockLength(expected: count, actual: data.count) }
        bytes.replaceSubrange(offset..<(offset + count), with: data)
    }
}
