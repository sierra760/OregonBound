import Testing
@testable import OregonBound

struct OriginalManagementAlertsTests {
    @Test func incorrectAndEmptyUseDifferentSystemIconsAndExactText() {
        let enable = OriginalManagementAlerts.presentation(.enableIncorrectPassword)
        let change = OriginalManagementAlerts.presentation(.changeIncorrectPassword)
        let empty = OriginalManagementAlerts.presentation(.emptyNewPassword)
        #expect(enable.icon == .note && change.icon == .note && empty.icon == .stop)
        #expect(enable.text == "That was not the correct password.  Please try again.")
        #expect(enable.text == change.text)
        #expect(empty.text == "You have not entered a new password.  Your password must be at least one character long.")
        #expect(enable.selectionBeforePresentation == .init(item:5,start:0,end:2000))
        #expect(change.selectionBeforePresentation == .init(item:6,start:0,end:1000))
        #expect(empty.selectionBeforePresentation == nil)
        #expect(enable.resourceID == 2003 && enable.defaultItem == 1 && enable.alertSoundCount == 0)
    }
    @Test func fixedContentGeometryIsSharedAndHasNoModernTitle() {
        for purpose in OriginalManagementAlerts.Purpose.allCases {
            let p = OriginalManagementAlerts.presentation(purpose)
            #expect(p.contentBounds == .init(top:0,left:0,bottom:125,right:300))
            #expect(p.messageBounds == .init(top:7,left:72,bottom:90,right:295))
            #expect(p.iconBounds == .init(top:10,left:20,bottom:42,right:52))
            #expect(p.buttonBounds == .init(top:100,left:120,bottom:120,right:180))
        }
    }
    @Test func nilFilterDoesNotInheritOuterCancelShortcutOrTimeOut() {
        #expect(OriginalManagementAlerts.response(to:.key(macRoman:13,command:false)) == .dismiss(item:1))
        #expect(OriginalManagementAlerts.response(to:.key(macRoman:3,command:false)) == .dismiss(item:1))
        #expect(OriginalManagementAlerts.response(to:.key(macRoman:27,command:false)) == .remain)
        #expect(OriginalManagementAlerts.response(to:.key(macRoman:46,command:true)) == .remain)
        #expect(OriginalManagementAlerts.response(to:.button(2)) == .remain)
        #expect(OriginalManagementAlerts.response(to:.outsideMouseDown) == .errorSoundAndRemain)
        #expect(OriginalManagementAlerts.response(to:.other) == .remain)
    }
    @Test func alertCentersOverMainWindowAndFallsBackOnlyWhenOutsideDesktop() {
        let window = OriginalManagementAlerts.Rect(top:50,left:100,bottom:370,right:612)
        let screen = OriginalManagementAlerts.Rect(top:0,left:0,bottom:480,right:640)
        let centered = OriginalManagementAlerts.bounds(mainWindowGlobalBounds:window,screenBounds:screen) { _ in true }
        #expect(centered == .init(top:147,left:206,bottom:272,right:506))
        let fallback = OriginalManagementAlerts.bounds(mainWindowGlobalBounds:window,screenBounds:screen) { _ in false }
        #expect(fallback == .init(top:187,left:170,bottom:312,right:470))
    }
}
