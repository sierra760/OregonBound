import XCTest
@testable import OregonBound

final class OriginalManagementTextEditTests: XCTestCase {
    typealias R = OriginalManagementTextEdit
    func testChangeReturnUsesDialogTabWhileTabSelectsNextField() {
        for field in [R.Field.oldPassword, .newPassword, .hint] {
            for kind in [R.EventKind.keyDown, .autoKey] {
                for key: UInt8 in [3,13] {
                    XCTAssertEqual(R.changeKey(key, eventKind: kind, field: field, textByteCount: 10, selection: 10..<10), .forwardToDialog(9))
                }
            }
        }
        XCTAssertEqual(R.changeKey(9, field: .oldPassword, textByteCount: 10, selection: 10..<10), .selectAll(.newPassword))
        XCTAssertEqual(R.changeKey(9, field: .newPassword, textByteCount: 10, selection: 10..<10), .selectAll(.hint))
        XCTAssertEqual(R.changeKey(9, field: .hint, textByteCount: 10, selection: 10..<10), .selectAll(.oldPassword))
    }
    func testAllPasswordBytesMatchWhitelistAndUnreachableDeleteRemap() {
        for value in 0...255 {
            let key = UInt8(value)
            let expected: R.Action
            switch key {
            case 3,13: expected = .forwardToDialog(9)
            case 9: expected = .selectAll(.newPassword)
            case 8,28...31,33...126: expected = .forwardToDialog(key)
            default: expected = .ignored
            }
            XCTAssertEqual(R.changeKey(key, field: .oldPassword, textByteCount: 0, selection: 0..<0), expected, "byte\(value)")
        }
    }
    func testCapCountsBytesMinusSelectionAndAlsoBlocksArrows() {
        for key: UInt8 in [28,29,30,31,33,126] {
            XCTAssertEqual(R.changeKey(key, field: .newPassword, textByteCount: 10, selection: 10..<10), .beep)
            XCTAssertEqual(R.changeKey(key, field: .newPassword, textByteCount: 10, selection: 9..<10), .forwardToDialog(key))
        }
        XCTAssertEqual(R.changeKey(8, field: .newPassword, textByteCount: 100, selection: 100..<100), .forwardToDialog(8))
        XCTAssertEqual(R.changeKey(65, field: .newPassword, textByteCount: 100, selection: 9..<100), .forwardToDialog(65))
    }
    func testHintProbeKeepsOriginalForwardedByteAndNoASCIIOrStorageCap() {
        for key: UInt8 in [0,8,27,32,127,165,255] {
            let probe: UInt8 = (key == 27 || key == 127) ? 8 : key
            XCTAssertEqual(R.changeKey(key, field: .hint, textByteCount: 255, selection: 255..<255), .probeHint(probeByte: probe, forwardedByte: key))
        }
        XCTAssertEqual(R.resolveHintProbe(lineCount: 3, forwardedByte: 127), .forwardToDialog(127))
        XCTAssertEqual(R.resolveHintProbe(lineCount: 4, forwardedByte: 65), .beep)
        XCTAssertEqual(R.resolveHintProbe(lineCount: nil, forwardedByte: 65), .beep)
    }
    func testEnableSeparatesVisibleMaskAndHiddenKey() {
        for value in 0...255 {
            let key = UInt8(value)
            let expected: R.Action
            switch key {
            case 3,13: expected = .activateDefault
            case 9: expected = .selectAll(.enablePassword)
            case 8: expected = .maskedKey(visibleByte: 8, hiddenByte: 8)
            case 28...31: expected = .maskedKey(visibleByte: key, hiddenByte: nil)
            case 33...126: expected = .maskedKey(visibleByte: 0xa5, hiddenByte: key)
            default: expected = .ignored
            }
            XCTAssertEqual(R.enableKey(key), expected, "byte\(value)")
        }
        XCTAssertEqual(R.enableKey(13, eventKind: .autoKey), .ignored)
        XCTAssertEqual(R.enableKey(9, eventKind: .autoKey), .selectAll(.enablePassword))
    }
    func testMacRomanAndCommitAreByteExactWithoutTypedSanitizing() throws {
        XCTAssertEqual(try R.encodedBytes("é •"), [0x8e,32,0xa5])
        XCTAssertThrowsError(try R.encodedBytes("🙂"))
        XCTAssertEqual(R.committedPassword([32,0x8e,13,0xa5,1,2,3,4,5,6,7]), [32,0x8e,13,0xa5,1,2,3,4,5,6])
        XCTAssertEqual(R.fontResource, 5478)
        XCTAssertEqual(R.hintWidth, 135)
    }
    func testSystemClipboardDispatchUsesPostFilterCharacter() {
        XCTAssertEqual(R.systemDialogKey(118, command: true, hasSelection: false), .paste)
        XCTAssertEqual(R.systemDialogKey(67, command: true, hasSelection: true), .copy)
        XCTAssertEqual(R.systemDialogKey(120, command: true, hasSelection: true), .cut)
        XCTAssertEqual(R.systemDialogKey(120, command: true, hasSelection: false), .ignored)
        XCTAssertEqual(R.systemDialogKey(0xa5, command: true, hasSelection: true), .ignored)
        XCTAssertEqual(R.systemDialogKey(65, command: true, hasSelection: true), .ignored)
        XCTAssertEqual(R.systemDialogKey(65, command: false, hasSelection: true), .textEditKey(65))
        XCTAssertEqual(R.systemDialogKey(0x10, virtualKey: 0x76, command: false, hasSelection: false), .paste)
        XCTAssertEqual(R.systemDialogKey(0x10, virtualKey: 0, command: false, hasSelection: true), .ignored)
        // The Change filter examines only the current text + selected range.
        XCTAssertEqual(R.changeKey(118, field: .newPassword, textByteCount: 9, selection: 9..<9), .forwardToDialog(118))
        // It never sees the clipboard length; DSEdit's later operation is TEPaste.
        XCTAssertEqual(R.changeKey(118, field: .newPassword, textByteCount: 10, selection: 10..<10), .beep)
    }

}
