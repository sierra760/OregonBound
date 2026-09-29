import XCTest
@testable import OregonBound

final class OriginalJournalLayoutTests: XCTestCase {
    private func layout(_ text: String, width: Int = 247, bold: Bool = false) throws -> OriginalJournalLayout.RecordLayout {
        let count = text.data(using: .macOSRoman)!.count
        return try OriginalJournalLayout.layout(text: text, isBold: bold, prefixWidths: Array(0...count), contentWidth: width)
    }
    func testUnwrappedPascalBytesFaceAndCoordinates() throws {
        let plain = try layout("Heavy fog.")
        XCTAssertEqual(plain.pascalBytes, Data([10] + Array("Heavy fog.".utf8)))
        XCTAssertEqual(plain.fragments.map(\.text),["Heavy fog."])
        XCTAssertEqual(plain.fragments.map(\.pascalStart),[1])
        XCTAssertEqual(plain.fragments.map(\.pascalEnd),[11])
        XCTAssertEqual(plain.fragments.map(\.x),[3])
        XCTAssertEqual(plain.fontResource,23522)
        XCTAssertEqual(try layout("A fire.",bold:true).fontResource,17847)
        XCTAssertEqual(try layout("").fragments.count,0)
    }
    func testBreakAtExactWidthIncludesTheSpaceAndIndentsContinuation() throws {
        let result = try layout("1234567890123456789 X",width:26)
        XCTAssertEqual(result.fragments.map(\.text),["1234567890123456789 ","X"])
        XCTAssertEqual(result.fragments.map(\.x),[3,15])
        XCTAssertFalse(result.wasTruncated)
    }
    func testCarriageReturnIsInDrawTextRangeButNotBitmapLineBreak() throws {
        let result = try layout("one\rtwo\r")
        XCTAssertEqual(result.fragments.map(\.text),["one\r","two\r"])
        XCTAssertEqual(result.fragments.map(\.drawingText),["one","two"])
        XCTAssertEqual(result.pascalBytes,Data([8,111,110,101,13,116,119,111,13]))
    }
    func testLiteralFourthLineMutationKeepsEllipsisOutsideDrawnBoundary() throws {
        let result = try layout(String(repeating:"a ",count:40),width:26)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.fragments.map(\.pascalStart),[1,21,27,33])
        XCTAssertEqual(result.fragments.map(\.pascalEnd),[21,27,33,35])
        XCTAssertEqual(result.fragments.map(\.text),[String(repeating:"a ",count:10),"a a a ","a a a ","a "])
        XCTAssertEqual(result.pascalBytes.first,36)
        XCTAssertEqual(result.pascalBytes.last,0xc9)
        XCTAssertEqual(result.pascalBytes[35],97) // Retained a, also beyond drawn end35.
        XCTAssertFalse(result.fragments.contains { $0.bytes.contains(0xc9) })
    }
    func testViewportClampsToEightLinesAndPreservesContinuationIndentWhenScrolled() throws {
        let records = try (0..<10).map { try layout("Entry \($0)") }
        let top = OriginalJournalLayout.viewport(records:records,firstLine:0)
        XCTAssertEqual(top.map(\.globalLine),Array(0..<8))
        XCTAssertEqual(top.map(\.baselineY),[12,24,36,48,60,72,84,96])
        XCTAssertEqual(top.map(\.glyphTopY),[3,15,27,39,51,63,75,87])
        let bottom = OriginalJournalLayout.viewport(records:records,firstLine:999)
        XCTAssertEqual(bottom.map(\.globalLine),Array(2..<10))
        XCTAssertEqual(bottom.first?.recordIndex,2)
        let wrapped = try layout("one\rtwo\rthree\rfour")
        let continuation = OriginalJournalLayout.viewport(records:[wrapped]+records,firstLine:1)
        XCTAssertEqual(continuation.first?.lineInRecord,1)
        XCTAssertEqual(continuation.first?.x,15)
        XCTAssertEqual(continuation.first?.baselineY,12)
    }
    func testUnsafeInputsReturnErrorsInsteadOfSubstituteWrapping() throws {
        XCTAssertThrowsError(try layout(String(repeating:"x",count:30),width:26)) { error in
            XCTAssertEqual(error as? OriginalJournalLayout.LayoutError,.originalWordBreakUnderflow)
        }
        XCTAssertThrowsError(try layout(String(repeating:"x",count:255),width:1000)) { error in
            XCTAssertEqual(error as? OriginalJournalLayout.LayoutError,.originalByteCursorWrap)
        }
        XCTAssertThrowsError(try OriginalJournalLayout.layout(text:"🌲",prefixWidths:[0,1]))
        XCTAssertThrowsError(try OriginalJournalLayout.layout(text:"aa",prefixWidths:[0,2,1]))
        XCTAssertThrowsError(try layout("x",width:10))
    }
}
