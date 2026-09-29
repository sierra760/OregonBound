import XCTest
@testable import OregonBound

final class OriginalSaveJournalTests: XCTestCase {
    private func record(_ data: [UInt8]) throws -> OriginalSaveJournal.Record {
        try XCTUnwrap(OriginalSaveJournal(usedBytes: Data(data)).records.first)
    }
    func testAllFixedOpcodeRangeBoundariesAndRawRoundTrip() throws {
        let sizes = [(0,2),(19,2),(20,2),(62,2),(63,16),(69,16),(70,12),(84,12),(85,4),(95,4),(105,4),(111,4),(120,6)]
        let bytes = sizes.flatMap { opcode, size in [UInt8(opcode)] + Array(repeating: UInt8(0xa5), count: size - 1) }
        let journal = try OriginalSaveJournal(usedBytes: Data(bytes))
        XCTAssertEqual(journal.records.map { $0.rawBytes.count }, sizes.map(\.1))
        XCTAssertEqual(journal.data, Data(bytes))
        XCTAssertEqual(journal.records.last?.offset, bytes.count - 6)
    }
    func testSpeechUsesLengthPrefixedRecipientBytesAndPreservesOddPadding() throws {
        let bytes: [UInt8] = [118, 7, 3, 72, 101, 121, 2, 4, 9, 0xab]
        let r = try record(bytes)
        XCTAssertEqual(r.speech?.message, "Hey")
        XCTAssertEqual(r.speech?.recipientWagonSlots, [4, 9])
        XCTAssertEqual(r.rawBytes, Data(bytes))
        let broadcast = try record([119, 0, 2, 72, 105, 0xfe])
        XCTAssertEqual(broadcast.speech?.message, "Hi")
        XCTAssertNil(broadcast.speech?.recipientWagonSlots)
    }
    func testDateAndMixedWidthInventoryFields() throws {
        let date = try record([120, 0, 7, 56, 4, 6])
        XCTAssertEqual(date.date, .init(year: 1848, month: 4, day: 6))
        let supplies = try XCTUnwrap(record([68, 0, 12, 10, 1, 2, 1, 44, 3, 232, 0, 1, 0x86, 0xa0, 3, 0xee]).supplies)
        XCTAssertEqual(supplies.rawOxen, 12)
        XCTAssertEqual(supplies.ammunition, 300)
        XCTAssertEqual(supplies.food, 1000)
        XCTAssertEqual(supplies.cashCents, 100000)
        XCTAssertEqual(supplies.wheels, 1)
        XCTAssertEqual(supplies.axles, 2)
        XCTAssertEqual(supplies.tongues, 3)
    }
    func testUnsupportedOpcodeAndTruncatedPayloadNeverResynchronize() throws {
        for opcode: UInt8 in [96, 104, 112, 117, 121, 255] {
            XCTAssertThrowsError(try OriginalSaveJournal(usedBytes: Data([0,0,opcode,0]))) { error in
                XCTAssertEqual(error as? OriginalSaveJournal.DecodeError, .unsupportedOpcode(opcode, offset: 2))
            }
        }
        for bytes: [UInt8] in [[0], [63,0], [120,0,7,56,4], [119,0,3,65], [118,0,0], [119,0,0]] {
            XCTAssertThrowsError(try OriginalSaveJournal(usedBytes: Data(bytes)))
        }
    }
    func testVisibleSimpleEventsAndDateUseSuppliedOriginalStrings() throws {
        let strings: (Int,Int)->String? = { resource, item in
            switch (resource,item) {
            case (1501,1): return "Heavy fog"
            case (3014,4): return "April"
            case (1502,7): return "^0 has a broken arm"
            case (1502,24): return "You changed your rations to ^5"
            case (3010,2): return "Meager"
            default: return nil
            }
        }
        func text(_ bytes: [UInt8]) throws -> String? {
            OriginalSaveJournal.presentation(of: try record(bytes), localWagonSlot: 0, strings: strings,
                memberName: { wagon, member in wagon == 0 && member == 2 ? "Jane" : nil }).text
        }
        XCTAssertEqual(try text([0,0]), "Heavy fog.")
        XCTAssertEqual(try text([120,0,7,56,4,6]), "• April 6, 1848 •")
        XCTAssertEqual(try text([26,64]), "Jane has a broken arm.")
        XCTAssertEqual(try text([43,32]), "You changed your rations to meager.")
        XCTAssertNil(try text([70,0,0,0,0,0,0,0,0,0,0,0]))
    }
}
