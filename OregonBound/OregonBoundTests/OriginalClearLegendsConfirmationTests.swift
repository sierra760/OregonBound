import Testing
@testable import OregonBound

struct OriginalClearLegendsConfirmationTests {
    @Test func recoveredStopAlertResourceAndLayout() {
        typealias R = OriginalClearLegendsConfirmation
        #expect(R.resourceID == 2045)
        #expect(R.icon == .stop)
        #expect(R.contentBounds == .init(top: 0, left: 0, bottom: 94, right: 270))
        #expect(R.messageBounds == .init(top: 13, left: 65, bottom: 54, right: 265))
        #expect(R.iconBounds == .init(top: 10, left: 20, bottom: 42, right: 52))
        #expect(R.noBounds == .init(top: 65, left: 57, bottom: 85, right: 117))
        #expect(R.yesBounds == .init(top: 65, left: 153, bottom: 85, right: 213))
        #expect(R.frameExtent == 8)
        #expect(R.alertSoundCount == 0)
        #expect(!R.waitsForApplicationAudio)
    }
    @Test func onlyYesChoosesRestoreAndDefaultIsNo() {
        typealias R = OriginalClearLegendsConfirmation
        #expect(R.response(to: .button(2)) == .dismiss(item: 2))
        #expect(R.response(to: .button(1)) == .dismiss(item: 1))
        for command in [false, true] {
            for byte: UInt8 in [3, 13] {
                #expect(R.response(to: .key(macRoman: byte, command: command)) == .dismiss(item: 1))
            }
            for byte: UInt8 in [27, 46, 65, 89, 121] {
                #expect(R.response(to: .key(macRoman: byte, command: command)) == .remain)
            }
        }
        #expect(R.response(to: .button(3)) == .remain)
        #expect(R.response(to: .outsideMouseDown) == .errorSoundAndRemain)
        #expect(R.response(to: .other) == .remain)
    }
    @Test func centersOverMainWindowWithIntegerDivision() {
        let bounds = OriginalClearLegendsConfirmation.centeredContent(in: .init(top: 0, left: 0, bottom: 322, right: 512))
        #expect(bounds == .init(top: 114, left: 121, bottom: 208, right: 391))
        // Editor content starts(106,41); nested content is(15,73), outer frame(7,65).
        #expect(bounds.left - 106 - 8 == 7)
        #expect(bounds.top - 41 - 8 == 65)
        #expect(OriginalClearLegendsConfirmation.centeredContent(in: .init(top: 31, left: 81, bottom: 354, right: 594)) == .init(top: 145, left: 202, bottom: 239, right: 472))
    }
}
