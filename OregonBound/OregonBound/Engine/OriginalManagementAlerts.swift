/// Original nested system alerts used by CODE15's Management password dialogs.
/// Content geometry comes from ALRT/DITL2003; outer System window framing is
/// intentionally separate. See ORIGINAL_MANAGEMENT_ALERTS.md.
enum OriginalManagementAlerts {
    enum Purpose: CaseIterable {
        case enableIncorrectPassword, changeIncorrectPassword, emptyNewPassword
    }
    enum Icon: Int { case stop = 0, note = 1 }
    struct Rect: Equatable {
        var top: Int; var left: Int; var bottom: Int; var right: Int
        var width: Int { right-left }
        var height: Int { bottom-top }
    }
    struct Selection: Equatable {
        let item: Int
        let start: Int
        let end: Int
    }
    struct Presentation: Equatable {
        let purpose: Purpose
        let icon: Icon
        let text: String
        let selectionBeforePresentation: Selection?
        var resourceID: Int { 2003 }
        var windowFrameExtent: Int { 8 } // System7 WDEF0:0728–074c.
        var contentBounds: Rect { Rect(top:0,left:0,bottom:125,right:300) }
        var messageBounds: Rect { Rect(top:7,left:72,bottom:90,right:295) }
        var iconBounds: Rect { Rect(top:10,left:20,bottom:42,right:52) }
        var buttonBounds: Rect { Rect(top:100,left:120,bottom:120,right:180) }
        var buttonTitle: String { "OK" }
        var defaultItem: Int { 1 }
        var alertSoundCount: Int { 0 }
        var iconFilename: String { "system7_alert_icon_\(icon.rawValue).png" }
    }

    static func presentation(_ purpose: Purpose) -> Presentation {
        let incorrect = "That was not the correct password.  Please try again."
        switch purpose {
        case .enableIncorrectPassword:
            // CODE15:0674–0686 selects hidden edit item5 before nested NoteAlert.
            return Presentation(purpose:purpose,icon:.note,text:incorrect,
                                selectionBeforePresentation:Selection(item:5,start:0,end:2000))
        case .changeIncorrectPassword:
            // CODE15:00b4–00c4 selects old password item6 before nested NoteAlert.
            return Presentation(purpose:purpose,icon:.note,text:incorrect,
                                selectionBeforePresentation:Selection(item:6,start:0,end:1000))
        case .emptyNewPassword:
            // CODE15:03d4–03f8 -> CODE1:0670 StopAlert. DITL '^0.' adds period.
            return Presentation(purpose:purpose,icon:.stop,
                                text:"You have not entered a new password.  Your password must be at least one character long.",
                                selectionBeforePresentation:nil)
        }
    }

    enum Event { case key(macRoman: UInt8, command: Bool), button(Int), outsideMouseDown, other }
    enum Response: Equatable { case remain, dismiss(item: Int), errorSoundAndRemain }
    /// Both callers pass NIL filter: only Return/Enter are the standard keyboard
    /// equivalents. The outer Management dialog's Command-period does not run.
    static func response(to event: Event) -> Response {
        switch event {
        case .key(let code, _): return code == 13 || code == 3 ? .dismiss(item:1) : .remain
        case .button(let item): return item == 1 ? .dismiss(item:1) : .remain
        case .outsideMouseDown: return .errorSoundAndRemain
        case .other: return .remain
        }
    }

    /// CODE1:0208–035e centers over the GAME window, then checks actual desktop
    /// region containment. Caller supplies the region test (not a guessed rect).
    /// Fallback uses saved screen right/bottom and20px menu area exactly as code.
    static func bounds(mainWindowGlobalBounds: Rect?, screenBounds: Rect,
                       desktopContains: (Rect) -> Bool) -> Rect {
        let host = mainWindowGlobalBounds ?? screenBounds
        let x = host.left + (host.width-300)/2
        let y = host.top + (host.height-125)/2
        let proposed = Rect(top:y,left:x,bottom:y+125,right:x+300)
        guard !desktopContains(proposed) else { return proposed }
        let fallbackX = (screenBounds.right-300)/2
        let fallbackY = 20+(screenBounds.bottom-20-125)/2
        return Rect(top:fallbackY,left:fallbackX,bottom:fallbackY+125,right:fallbackX+300)
    }
}
