import Foundation
import Testing
@testable import OregonBound

struct OriginalTextEditLineLayoutTests {
    private func lines(_ text: String, width: Int = 10) throws -> [Int] {
        let bytes = Array(text.data(using: .macOSRoman)!)
        var widths = [0]
        for byte in bytes { widths.append(widths.last! + (byte == 13 ? 0 : 1)) }
        return try OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: widths, width: width).lineStarts
    }

    @Test func emptyAndTrailingCarriageReturnDoNotInventEmptyLines() throws {
        #expect(try lines("") == [0])
        #expect(try lines("one") == [0,3])
        #expect(try lines("one\r") == [0,4])
        #expect(try lines("one\r\r") == [0,4,5])
        #expect(try lines("\r\r\r") == [0,1,2,3])
        #expect(try lines("a\nb") == [0,3]) // LF is not the end-of-line hook.
    }

    @Test func exactPixelBoundaryBacksOffTheHitCharacter() throws {
        #expect(try lines("123456789", width: 10) == [0,9])
        #expect(try lines("1234567890", width: 10) == [0,9,10])
        #expect(try lines("12345678901", width: 10) == [0,9,11])
        #expect(try lines("abc def", width: 7) == [0,4,7])
    }

    @Test func overflowSpacesStayOnPreviousLineAndStopAtCarriageReturn() throws {
        #expect(try lines("123456789    x", width: 10) == [0,13,14])
        #expect(try lines("123456789    ", width: 10) == [0,13])
        #expect(try lines("123456789 \r x", width: 10) == [0,11,13])
        #expect(try lines("123456789\t\nx", width: 10) == [0,11,12])
    }

    @Test func byteLowWordBoundaryRetainsLiteralOriginalScanBranch() throws {
        #expect(try lines(String(repeating: "A", count: 255) + "    B", width: 257) == [0,256,260])
    }

    @Test(.enabled(if: GameData.isReady)) func originalChicagoHintHasThreeLinesAtTheRecoveredBoundary() throws {
        let font = try #require(BitmapFont.chicago12)
        // 16 A advances (8 each) + E (7) is exactly135, so E starts line2.
        let text = String(repeating: "A", count: 16) + "E"
        let bytes = Array(text.data(using: .macOSRoman)!)
        let widths = try #require(font.prefixWidths(text))
        #expect(widths.last == 135)
        #expect(try OriginalTextEditLineLayout.layout(bytes: bytes, prefixWidths: widths).lineStarts == [0,16,17])
        let threeLines = String(repeating: "A", count: 48)
        let result = try OriginalTextEditLineLayout.layout(bytes: Array(threeLines.utf8),
            prefixWidths: #require(font.prefixWidths(threeLines)))
        #expect(result.lineCount == 3)
        let fourLines = threeLines + "A"
        #expect(try OriginalTextEditLineLayout.layout(bytes: Array(fourLines.utf8),
            prefixWidths: #require(font.prefixWidths(fourLines))).lineCount == 4)
    }

    @Test func rejectsBadMetricsAndNonAdvancingWidthsWithoutLooping() throws {
        #expect(throws: OriginalTextEditLineLayout.LayoutError.self) {
            try OriginalTextEditLineLayout.layout(bytes: [65], prefixWidths: [0])
        }
        #expect(throws: OriginalTextEditLineLayout.LayoutError.self) {
            try OriginalTextEditLineLayout.layout(bytes: [65,66], prefixWidths: [0,2,1])
        }
        #expect(throws: OriginalTextEditLineLayout.LayoutError.self) {
            try OriginalTextEditLineLayout.layout(bytes: [65], prefixWidths: [0,135])
        }
    }
}
