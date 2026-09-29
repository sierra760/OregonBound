import SwiftUI

/// CODE12:00b2–026c, DITL2050, PICT2050–2052. Each presentation starts at page1.
struct OriginalIntroductionPane: View {
    @State private var page = OriginalPreferences.Introduction()
    let done: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            // Original picture frames start at(-1,-1); OffsetRect adds(10,6).
            OriginalTextPicture(resource: page.pictureResource).offset(x: 9, y: 5)
            OriginalManagementButton(title: "Previous", width: 70, enabled: page.canGoPrevious) { page.previous() }
                .offset(x: 63, y: 274)
            OriginalManagementButton(title: "Done", width: 70, isDefault: page.doneIsDefault, action: done)
                .offset(x: 211, y: 274)
            OriginalManagementButton(title: "Next", width: 70, isDefault: !page.doneIsDefault,
                                     enabled: page.canGoNext) { page.next() }.offset(x: 359, y: 274)
            Button("") { if page.doneIsDefault { done() } else { page.next() } }
                .keyboardShortcut(.defaultAction).frame(width: 0, height: 0).hidden().accessibilityHidden(true)
        }.frame(width: 492, height: 302).clipped().font(.system(size: 12)).foregroundStyle(.black)
    }
}

/// Management item1 calls the ordinary modal dialog helper with DLOG/DITL2040.
struct OriginalAboutManagementPane: View {
    let done: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            OriginalText(text: "About Management Options", font: .chicago12).frame(width: 184, height: 20, alignment: .topLeading).offset(x: 148, y: 16)
            OriginalText(text: "You can use Management Options to clear the “List of Legends,” adjust the simulation speed and hunting time, determine network use (if any), and change the management password.", font: .chicago12, width: 462)
                .frame(width: 462, height: 48, alignment: .topLeading).offset(x: 16, y: 46)
            OriginalText(text: "In short, Management Options allow you to customize Oregon Bound to your particular educational needs.", font: .chicago12, width: 462)
                .frame(width: 462, height: 37, alignment: .topLeading).offset(x: 16, y: 109)
            OriginalText(text: "To prevent users from unauthorized modification of the simulation, you have to use a password in order to gain access to the Management Options.", font: .chicago12, width: 462)
                .frame(width: 462, height: 48, alignment: .topLeading).offset(x: 16, y: 153)
            OriginalText(text: "See the Oregon Trail User’s Guide for instructions on gaining access to the Management Options.", font: .chicago12, width: 462)
                .frame(width: 462, height: 32, alignment: .topLeading).offset(x: 16, y: 213)
            OriginalManagementButton(title: "OK", isDefault: true, action: done)
                .offset(x: 214, y: 268).keyboardShortcut(.defaultAction)
        }.frame(width: 488, height: 298).font(.system(size: 12)).foregroundStyle(.black)
    }
}
