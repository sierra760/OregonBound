import XCTest
@testable import OregonBound

final class OriginalSaveArchiveTests: XCTestCase {
    // Deliberately synthetic bytes, not represented as an emulator-produced save.
    private func fixture(extra: [UInt8] = []) -> Data {
        var bytes = (0..<14440).map { UInt8(truncatingIfNeeded: $0 * 37 + 19) }
        bytes.replaceSubrange(0..<6, with: [0x4d, 0x45, 0x43, 0x43, 0, 2])
        bytes[40 + 0x240] = 1
        bytes[40 + 0x0a] = 0
        return Data(bytes + extra)
    }

    func testRoundTripPreservesEveryUnknownAndTrailingByte() throws {
        let bytes = fixture(extra: [0x22, 0xff, 0x80])
        let archive = try OriginalSaveArchive(data: bytes)
        XCTAssertEqual(archive.data, bytes)
        XCTAssertEqual(archive.worldBytes.count, 4126)
        XCTAssertEqual(archive.journalStateBytes.count, 34)
        XCTAssertEqual(archive.journalBytes.count, 10240)
        XCTAssertEqual(archive.trailingBytes, Data([0x22, 0xff, 0x80]))
        XCTAssertTrue(archive.hasCanonicalSignature)
        XCTAssertEqual(try archive.singleWagonPlayerIndex(), 0)
    }

    func testKnownFieldsUseBigEndianAndPreserveSurroundings() throws {
        let original = fixture()
        var archive = try OriginalSaveArchive(data: original)
        archive.setWorldWord(.year, 1848)
        archive.setWorldByte(.destinationRaw, 255)
        try archive.setPlayerWord(.food, 1000, record: 0)
        XCTAssertEqual(archive.worldWord(.year), 1848)
        XCTAssertEqual(archive.destinationIndex, -1)
        XCTAssertEqual(try archive.playerWord(.food, record: 0), 1000)
        let changed = Set(original.indices.filter { original[$0] != archive.data[$0] })
        XCTAssertEqual(changed, Set([40, 41, 40 + 0x238, 40 + 0x25e + 0x52, 40 + 0x25e + 0x53]))
        XCTAssertEqual(Array(archive.data[40..<42]), [7, 56])
    }

    func testOriginalVersionCheckDoesNotInventMagicValidation() throws {
        var bytes = fixture()
        bytes[0] = 0x99
        let archive = try OriginalSaveArchive(data: bytes)
        XCTAssertFalse(archive.hasCanonicalSignature)
        XCTAssertEqual(archive.data, bytes)
        bytes[5] = 3
        XCTAssertThrowsError(try OriginalSaveArchive(data: bytes))
        XCTAssertThrowsError(try OriginalSaveArchive(data: fixture().prefix(14439)))
    }

    func testLoadResetsSlotIndexedFlagsRatherThanMappedRecords() throws {
        var archive = try OriginalSaveArchive(data: fixture())
        archive.setWorldByte(.wagonSlotCount, 2)
        var world = archive.worldBytes
        world[0x0a] = 3; world[0x0b] = 5
        try archive.replaceWorldBytes(world)
        let before = archive
        let loaded = try archive.applyingOriginalLoadFlagReset()
        XCTAssertEqual(loaded.worldByte(.flags), 0)
        for record in 0...1 {
            XCTAssertEqual(try loaded.playerByte(.flags, record: record), 0)
            XCTAssertEqual(try loaded.playerByte(.secondaryFlags, record: record), 0)
        }
        for record in [3, 5] {
            XCTAssertEqual(try loaded.playerBytes(record: record), try before.playerBytes(record: record))
        }
        XCTAssertEqual(archive, before)
        XCTAssertThrowsError(try archive.singleWagonPlayerIndex())
    }

    func testJournalCursorIsRelativeToSavedPointerAndRawStateIsRetained() throws {
        var archive = try OriginalSaveArchive(data: fixture())
        var state = archive.journalStateBytes
        state.replaceSubrange(0..<8, with: [0xff, 0xff, 0xff, 0xf0, 0, 0, 0, 0x10])
        try archive.replaceJournalStateBytes(state)
        XCTAssertEqual(archive.journalUsedByteCount, 32)
        XCTAssertEqual(archive.usedJournalBytes, archive.journalBytes.prefix(32))
        state.replaceSubrange(4..<8, with: [0, 1, 0, 0])
        try archive.replaceJournalStateBytes(state)
        XCTAssertNil(archive.journalUsedByteCount)
        XCTAssertEqual(archive.journalStateBytes, state)
    }

    func testBoundsRejectInvalidMutationWithoutChangingArchive() throws {
        var archive = try OriginalSaveArchive(data: fixture())
        let before = archive
        XCTAssertThrowsError(try archive.setPlayerWord(.food, 2, record: 32))
        XCTAssertThrowsError(try archive.playerBytes(record: -1))
        XCTAssertThrowsError(try archive.replaceWorldBytes(Data(repeating: 0, count: 4125)))
        XCTAssertEqual(archive, before)
        var world = archive.worldBytes
        world[0x0a] = 32
        try archive.replaceWorldBytes(world)
        XCTAssertThrowsError(try archive.singleWagonPlayerIndex())
    }
    func testNamesFollowWagonSlotMappingAndPreserveUnusedPascalBytes() throws {
        var archive = try OriginalSaveArchive(data: fixture())
        var world = archive.worldBytes
        world[0x0a] = 3
        try archive.replaceWorldBytes(world)
        let before = archive
        try archive.setMemberName("  éD ", memberSlot: 0, wagonSlot: 0)
        try archive.setMemberName("Jane", memberSlot: 1, wagonSlot: 0)
        try archive.setMemberName("Pete", memberSlot: 4, wagonSlot: 0)
        XCTAssertEqual(try archive.memberName(memberSlot: 0, wagonSlot: 0), "  éD ")
        XCTAssertEqual(try archive.memberName(memberSlot: 1, wagonSlot: 0), "Jane")
        XCTAssertEqual(try archive.memberName(memberSlot: 4, wagonSlot: 0), "Pete")
        XCTAssertEqual(try archive.playerBytes(record: 0), try before.playerBytes(record: 0))
        let player = try archive.playerBytes(record: 3)
        XCTAssertEqual(Array(player[6..<11]), [4, 74, 97, 110, 101])
        XCTAssertEqual(player[11], try before.playerBytes(record: 3)[11])
        let saved = archive
        XCTAssertThrowsError(try archive.setMemberName(String(repeating: "x", count: 16), memberSlot: 1, wagonSlot: 0))
        XCTAssertThrowsError(try archive.setMemberName("🐂", memberSlot: 1, wagonSlot: 0))
        XCTAssertEqual(archive, saved)
    }

    func testCashAndSparePartWordsRetainOriginalUnits() throws {
        var archive = try OriginalSaveArchive(data: fixture())
        try archive.setPlayerLong(.cashCents, 123456, record: 0)
        try archive.setPlayerWord(.spareWheels, 1, record: 0)
        try archive.setPlayerWord(.spareAxles, 2, record: 0)
        try archive.setPlayerWord(.spareTongues, 3, record: 0)
        XCTAssertEqual(try archive.playerLong(.cashCents, record: 0), 123456)
        let player = try archive.playerBytes(record: 0)
        XCTAssertEqual(Array(player[0x4c..<0x52]), [0, 1, 0, 2, 0, 3])
        XCTAssertEqual(Array(player[0x54..<0x58]), [0, 1, 0xe2, 0x40])
    }

}
