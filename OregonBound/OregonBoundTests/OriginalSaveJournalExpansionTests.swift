import XCTest
@testable import OregonBound

final class OriginalSaveJournalExpansionTests: XCTestCase {
    private func record(_ bytes: [UInt8]) throws -> OriginalSaveJournal.Record {
        try XCTUnwrap(OriginalSaveJournal(usedBytes: Data(bytes)).records.first)
    }
    private func text(_ bytes: [UInt8], local: Int = 0) throws -> String? {
        OriginalSaveJournal.presentation(of: try record(bytes), localWagonSlot: local,
            strings: { resource, index in
                guard let table = Self.tables[resource], table.indices.contains(index - 1) else { return nil }
                return table[index - 1]
            }, memberName: { wagon, _ in [0: "Alice", 1: "Bob", 2: "Carol"][wagon] }).text
    }
    private func trade(_ opcode: UInt8, counterparty: UInt8 = 1, requester: UInt8 = 0,
                       items: UInt8 = 0x76, received: Int32 = 1, given: Int32 = 12345) -> [UInt8] {
        func bytes(_ number: Int32) -> [UInt8] {
            (0..<4).reversed().map { UInt8(truncatingIfNeeded: UInt32(bitPattern: number) >> ($0 * 8)) }
        }
        return [opcode,counterparty,requester,items] + bytes(received) + bytes(given)
    }
    func testSupplyMixedUnitsOrderCashAndEmptyBranches() throws {
        let payload: [UInt8] = [0,3,1,1,2,1,44,3,232,0,0,0x30,0x39,3,0xee]
        XCTAssertEqual(try text([68] + payload), "You started down the trail with 2 oxen, 1 set of clothing, 300 bullets, 1 wagon wheel, 2 wagon axles, 3 wagon tongues, 1,000 pounds of food, and $123.45.")
        let zero = Array(repeating: UInt8(0), count: 15)
        XCTAssertEqual(try text([63]+zero), "You found an abandoned wagon, but there were no supplies to be scavenged.")
        XCTAssertEqual(try text([66]+zero), "Your wagon tipped but you lost nothing.")
        XCTAssertEqual(try text([65]+zero), "A fire in your wagon destroyed .")
        for opcode: UInt8 in 63...68 { XCTAssertNotNil(try text([opcode]+payload)) }
    }
    func testTradeRolesAndNibbleQuantitiesDoNotUseRawOxenUnits() throws {
        let bytes = trade(72, items: 0x70, received: 3)
        let decoded = try XCTUnwrap(record(bytes).trade)
        XCTAssertEqual(decoded.receivedItem, 0)
        XCTAssertEqual(decoded.givenItem, 7)
        XCTAssertEqual(decoded.givenQuantity, 12345)
        XCTAssertEqual(try text(bytes), "You give Bob $123.45 for 3 oxen.")
        XCTAssertEqual(try text(bytes, local: 1), "Alice gives you $123.45 for 3 oxen.")
        XCTAssertEqual(try text(bytes, local: 2), "Alice completed a trade with Bob.")
        XCTAssertEqual(try text(trade(79)), "You traded $123.45 for 1 pound of food.")
        XCTAssertEqual(try text(trade(79), local: 1), "You traded 1 pound of food for $123.45.")
    }
    func testTradeNothingZeroAndReservedPayloadAreExplicit() throws {
        XCTAssertEqual(try text(trade(79, items: 0x86, given: 1)), "You traded nothing for 1 pound of food.")
        XCTAssertEqual(try text(trade(79, items: 0x86, given: 0)), "You traded  for 1 pound of food.")
        XCTAssertNil(try text(trade(72, received: -1)))
        XCTAssertNil(try text(trade(72, items: 0xf6)))
        for opcode: UInt8 in 81...84 { XCTAssertNil(try text(trade(opcode))) }
        for opcode: UInt8 in 70...79 { XCTAssertNotNil(try text(trade(opcode))) }
        XCTAssertEqual(try record(trade(84, received: -1)).trade?.receivedQuantity, -1)
    }
    func testDecisionPrefixesAndAllRecoveredActionCodes() throws {
        for (opcode, prefix) in [(106,"The wagon train voted to "),(107,"The wagon train voted not to "),(108,"The captain decided to "),(109,"You decided to ")] {
            XCTAssertEqual(try text([UInt8(opcode),3,0,0xab]), prefix + "hunt.")
        }
        let actions: [(UInt8,UInt8,String)] = [
            (1,0,"call a time out"),(2,0,"continue"),(3,0,"hunt"),(4,1,"rest for one day"),
            (4,255,"rest for 255 days"),(5,1,"change the pace to strenuous"),(6,0,"exit the game"),
            (7,1,"elect Bob as the new captain"),(8,255,"change to a council form of government"),
            (8,0,"change to a captain form of government"),(9,0,"leave you behind"),
            (9,1,"leave Bob behind"),(10,0,"quit the game"),(17,0,"hold a conference")]
        for (action, parameter, suffix) in actions {
            XCTAssertEqual(try text([109,action,parameter,0xee]), "You decided to " + suffix + ".")
        }
        XCTAssertNil(try text([109,11,0,0]))
    }
    func testPackedCrossingMethodTrailAndHuntReturn() throws {
        let methods = ["ford", "caulk your wagon and float it across", "take a ferry across", "have an Indian guide help you cross"]
        for opcode: UInt8 in 106...109 {
            for method in 0..<4 {
                XCTAssertEqual(try text([opcode,130,UInt8(method << 5) | 31,0]), "You chose to " + methods[method] + " the river.")
            }
        }
        XCTAssertEqual(try text([109,66,0,0]), "You decided to take the trail to Independence, Missouri.")
        XCTAssertEqual(try text([109,66,17,0]), "You decided to take the Barlow Toll Road.")
        XCTAssertEqual(try text([105,255,200,0xa5]), "You brought back 200 pounds of food from hunting.")
        XCTAssertEqual(try record([105,255,200,0xa5]).decision, .huntReturn(food: 200))
        XCTAssertEqual(try text([111,255,255,0xa5]), "You are now traveling alone.")
    }
    func testContinuationFailureUsesOneBasedReasonAndCurrentWagonGrammar() throws {
        XCTAssertEqual(try text([110,0,1,0xa5]), "You can’t continue because you need some oxen.")
        XCTAssertEqual(try text([110,1,5,0xa5]), "You can’t continue because Bob is out hunting.")
        XCTAssertNil(try text([110,0,0,0]))
        XCTAssertEqual(try record([110,33,7,0]).decision, .unableToContinue(packedWagon: 33, reasonStringIndex: 7))
    }
    func testPunctuationCannotGrowAFullPascalString() throws {
        let full = String(repeating: "A", count: 255)
        let result = OriginalSaveJournal.presentation(of: try record([0,0]), localWagonSlot: 0,
            strings: { _, _ in full }, memberName: { _, _ in nil })
        XCTAssertEqual(result.text, full)
    }
    // Exact extracted resource strings, kept here to test the lookup/substitution contract.
    private static let tables: [Int: [String]] = [
        1500: ["A person in ^0’s wagon", "You", "^6’s wagon", " really", " and", "one ", " ", ", ", "council", "captain", "Good luck traveling the trail alone.  It can be tough when you don’t have others to help you", "The wagon train"],
        1503: ["You found ^2 in an abandoned wagon", "A thief stole ^2 from your wagon", "A fire in your wagon destroyed ^2.", "Your wagon tipped and you lost ^2.", "You bought ^2 at the store", "You started down the trail with ^2."],
        1523: ["You found an abandoned wagon, but there were no supplies to be scavenged", "", "^6’s wagon was damaged by fire", "Your wagon tipped but you lost nothing"],
        1505: ["Everyone has forgotten about your request to trade for ^2.", "You would like to receive ^2 in trade", "You give ^6 ^4 for ^2.", "You reject ^6’s offer to give you ^2 for ^4.", "You ignore ^6’s offer to give you ^2 for ^4.", "^6 no longer has ^2 that they agreed to give you", "You no longer have the ^4 to trade", "^6 doesn’t have space to carry the ^4 that you agreed to give them", "You don’t have space in your wagon to carry the ^2 that you agreed to trade for", "You traded ^4 for ^2.", "^3 completed a trade with ^0."],
        1525: ["", "^6 would like to receive ^2 in trade", "^6 gives you ^4 for ^2.", "^6 rejects your offer to trade ^2 for ^4.", "^6 ignores your offer to trade ^2 for ^4.", "You no longer have the ^2 to trade to ^6.", "^6 no longer has the ^4 to trade", "You don’t have space in your wagon to carry the ^4 that you agreed to trade for", "^6 doesn’t have space to carry the ^2 that you agreed to give them", "You traded ^2 for ^4.", ""],
        1507: ["You brought back ^5 pounds of food from hunting", "The wagon train voted to ", "The wagon train voted not to ", "The captain decided to ", "You decided to ", "^0 can’t continue because ^6 ", "call a time out", "continue", "take the trail to ", "You chose to ^5 the river", "ford", "caulk your wagon and float it across", "take a ferry across", "have an Indian guide help you cross", "hunt", "rest for one day", "rest for ^5 days", "change the pace to ^5", "quit the game", "exit the game", "elect ^6 as the new captain", "change to a ^5 form of government", "leave ^6 behind", "You are now traveling alone", "", "hold a conference"],
        3011: ["oxen", "sets of clothing", "bullets", "wagon wheels", "wagon axles", "wagon tongues", "pounds of food", "ox", "set of clothing", "bullet", "wagon wheel", "wagon axle", "wagon tongue", "pound of food", "nothing", "more "],
        3019: ["needs some oxen", "needs a wagon wheel", "needs a wagon axle", "needs a wagon tongue", "is out hunting", "is in the store", "does not have $5 to pay the toll"],
        3020: ["need some oxen", "need a wagon wheel", "need a wagon axle", "need a wagon tongue", "are out hunting", "are in the store", "do not have $5 to pay the toll"],
        3009: ["Steady", "Strenuous", "Grueling", "Resting", "Delayed", "Hunting", "In the store", "Voting", "Moving", "Stopped", "Crossing River", "Conference", "Trading"],
        3002: ["Independence, Missouri", "the Kansas River Crossing", "the Big Blue River Crossing", "Fort Kearney", "Chimney Rock", "Fort Laramie", "Independence Rock", "South Pass", "Fort Bridger", "the Green River Crossing", "Soda Springs", "Fort Hall", "the Snake River Crossing", "Fort Boise", "Grande Ronde in the Blue Mountains", "Fort Walla Walla", "The Dalles", "take the Barlow Toll Road", "raft down the Columbia River"],
    ]
}
