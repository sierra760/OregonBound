import XCTest
@testable import OregonBound

final class OriginalSaveJournalProjectionTests: XCTestCase {
    private func bytes(_ opcode: UInt8, _ actor: UInt8 = 0, parameter: UInt8 = 0) -> [UInt8] {
        let size: Int
        switch opcode {
        case 63...69: size = 16
        case 70...84: size = 12
        case 85...95,105...111: size = 4
        case 120: size = 6
        default: size = 2
        }
        var result = [opcode,actor] + Array(repeating: UInt8(0),count:size-2)
        if size > 2 { result[2] = parameter }
        return result
    }
    private func journal(_ rows: [[UInt8]]) throws -> OriginalSaveJournal {
        try .init(usedBytes:Data(rows.flatMap { $0 }))
    }
    private let date: [UInt8] = [120,0,7,56,4,1]
    func testLocalOnlyFamiliesMaskActorButKeepFirePublic() throws {
        for opcode: UInt8 in [20,25,36,43,63,64,66,67,68,69,105] {
            let source = try journal([bytes(opcode,64),bytes(opcode,65)])
            XCTAssertEqual(source.visibility(localWagonSlot:0),[true,false],"opcode \(opcode)")
        }
        let source = try journal([bytes(65,1),bytes(26,1),bytes(0,1)])
        XCTAssertEqual(source.visibility(localWagonSlot:0),[true,true,true])
    }
    func testTradeVisibilityDiffersFromTextPerspective() throws {
        for opcode: UInt8 in 70...84 {
            let source = try journal([bytes(opcode,1,parameter:2),bytes(opcode,0,parameter:2),bytes(opcode,1,parameter:0)])
            let expected: [Bool] = opcode == 71 || opcode == 72 ? [true,true,true]
                : opcode == 80 ? [true,false,false] : [false,true,true]
            XCTAssertEqual(source.visibility(localWagonSlot:0),expected,"opcode \(opcode)")
        }
        // Unlike packed actors, trade participant comparison does not mask high bits.
        XCTAssertEqual(try journal([bytes(79,32,parameter:33)]).visibility(localWagonSlot:0),[false])
    }
    func testCrossingDecisionAndPrivateSpeechFiltering() throws {
        for opcode: UInt8 in 106...109 {
            let source = try journal([bytes(opcode,130,parameter:96),bytes(opcode,130,parameter:97),bytes(opcode,3,parameter:97)])
            XCTAssertEqual(source.visibility(localWagonSlot:0),[true,false,true])
        }
        // Empty message, recipient-list length, recipients, alignment pad.
        let source = try journal([[118,1,0,2,3,0],[118,1,0,1,3,0],[118,32,0,0],[119,1,0,0]])
        XCTAssertEqual(source.visibility(localWagonSlot:0),[true,false,true,true])
    }
    func testDateHeadingVisibilityStopsAtNextDateAndKeepsBlankVisibleDay() throws {
        let source = try journal([date,bytes(20,1),date,bytes(20,0),date])
        XCTAssertEqual(source.visibility(localWagonSlot:0),[false,false,true,true,false])
        // Opcode80 observed by neither party is visible even though its template is empty.
        let blank = try journal([date,bytes(80,1,parameter:2)])
        XCTAssertEqual(blank.visibility(localWagonSlot:0),[true,true])
    }
    func testProjectionRetainsDatesHiddenRecordsAndEveryEightPhysicalCheckpoint() throws {
        let source = try journal([bytes(0),date,bytes(20,1),bytes(0),bytes(0),bytes(0),bytes(0),bytes(0),bytes(0)])
        let projection = source.project(localWagonSlot:0,strings: { resource,index in
            if resource == 1501 { return "Fog" }
            if resource == 3014 { return "April" }
            return nil
        },memberName:{ _,_ in nil },lineCount:{ _,_,_ in 1 })
        XCTAssertNil(projection.rows[0].date)
        XCTAssertEqual(projection.rows[2].date,.init(year:1848,month:4,day:1))
        XCTAssertFalse(projection.rows[2].isVisible)
        XCTAssertEqual(projection.rows[2].lineCount,0)
        XCTAssertEqual(projection.sparseIndex.map(\.recordIndex),[0,8])
        XCTAssertEqual(projection.sparseIndex.map(\.byteOffset),[0,20])
        XCTAssertEqual(projection.sparseIndex.map(\.firstLine),[0,7])
        XCTAssertEqual(projection.totalLineCount,8)
        XCTAssertEqual(projection.rows.map(\.record.rawBytes).reduce(into:Data()) { $0.append($1) },source.data)
    }
    func testUnresolvedVisibleTextDoesNotInventCumulativeLineIndex() throws {
        let source = try journal([date,bytes(85)] + Array(repeating:bytes(0),count:7))
        let projection = source.project(localWagonSlot:0,strings:{ resource,_ in resource == 3014 ? "April" : "Fog" },
                                        memberName:{ _,_ in nil },lineCount:{ _,_,_ in 1 })
        XCTAssertEqual(projection.unresolvedVisibleRows.map(\.record.opcode),[85])
        XCTAssertEqual(projection.rows[1].firstLine,1)
        XCTAssertNil(projection.rows[1].lineCount)
        XCTAssertNil(projection.rows[2].firstLine)
        XCTAssertNil(projection.sparseIndex[1].firstLine)
        XCTAssertNil(projection.totalLineCount)
        XCTAssertEqual(projection.sparseIndex[1].byteOffset,22)
    }
    func testBoldFaceUsesOriginalEventTableAndSenderPerspective() throws {
        let source = try journal([bytes(23),bytes(23,1),bytes(64),bytes(64,1),bytes(71,1),bytes(88),[119,1,0,0],date])
        XCTAssertEqual(source.records.map { OriginalSaveJournal.usesBoldFace($0,localWagonSlot:0) },[true,false,true,false,true,true,true,false])
    }
    func testLineCounterUsesStrictFitCRContinuationIndentAndCap() throws {
        func count(_ text: String,_ width: Int) throws -> Int {
            let n = text.data(using:.macOSRoman)!.count
            return try OriginalSaveJournal.wrappedLineCount(text:text,prefixWidths:Array(0...n),contentWidth:width)
        }
        XCTAssertEqual(try count("",262),0)
        XCTAssertEqual(try count("one\rtwo",262),2)
        XCTAssertEqual(try count("one\r",262),1)
        XCTAssertEqual(try count("1234567890123456789 X",26),2) // Exactly20 reaches break.
        XCTAssertEqual(try count(String(repeating:"a ",count:80),40),4)
        XCTAssertThrowsError(try count(String(repeating:"x",count:30),26)) { error in
            XCTAssertEqual(error as? OriginalSaveJournal.LineCountError,.originalWordBreakUnderflow)
        }
        XCTAssertThrowsError(try OriginalSaveJournal.wrappedLineCount(text:"x",prefixWidths:[0],contentWidth:262))
        XCTAssertThrowsError(try count(String(repeating:"x",count:255),1000)) { error in
            XCTAssertEqual(error as? OriginalSaveJournal.LineCountError,.originalByteCursorWrap)
        }
    }
}
