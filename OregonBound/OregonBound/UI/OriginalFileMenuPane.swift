import SwiftUI

/// DITL5230; embed in the original center-pane slot. There is no Cancel button.
struct OriginalExitGamePane: View {
    let departure: OriginalFileMenuRules.Departure
    let choose: (OriginalFileMenuRules.Choice) -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text: OriginalFileMenuRules.question(departure), width: 234).offset(x: 11, y: 25)
            OriginalButton(title: "Yes", isDefault: true) { choose(.yes) }
                .frame(width: 60, height: 20).offset(x: 28, y: 85).keyboardShortcut(.defaultAction)
            OriginalButton(title: "No") { choose(.no) }.frame(width: 60, height: 20).offset(x: 175, y: 85)
        }.frame(width: 262, height: 119)
    }
}

/// DITL6320, shared by ordinary Save and Yes in the departure confirmation.
struct OriginalSaveTimeOutPane: View {
    let done: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text: OriginalFileMenuRules.timeOutRequired, width: 236).offset(x: 12, y: 73)
            OriginalButton(title: "OK", isDefault: true, action: done)
                .frame(width: 60, height: 20).offset(x: 100, y: 168).keyboardShortcut(.defaultAction)
        }.frame(width: 262, height: 199)
    }
}

/// About page. Double-clicking the title opens System Information.
/// The caller supplies the system values shown there.
struct OriginalAboutPane: View {
    let systemInformation: [String]
    let tickCount: () -> UInt32
    let doubleClickTicks: UInt32
    var pollAudio: (Bool) -> Void = { _ in }
    let done: () -> Void
    @State private var state = OriginalAboutRules.State()
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            OriginalText(text: "Oregon Bound", font: .bold14)
                .scaleEffect(1.5).frame(width: 209, height: 54).offset(x: 5, y: 5)
                .contentShape(Rectangle()).onTapGesture { state.clickLogo(tick: tickCount(), doubleClickTicks: doubleClickTicks) }
            OriginalText(text: OriginalAboutRules.program, font: .chicago12).offset(x: 260, y: 2)
            OriginalText(text: OriginalAboutRules.version, font: .chicago12).offset(x: 261, y: 19)
            OriginalText(text: OriginalAboutRules.copyright, font: .geneva9).offset(x: 210, y: 36)
            OriginalText(text: OriginalAboutRules.license, font: .geneva9).offset(x: 210, y: 53)
            ForEach(Array(OriginalAboutRules.attribution.enumerated()), id: \.offset) { index, line in
                OriginalText(text: line, font: .geneva9)
                    .offset(x: 210, y: CGFloat(80 + index * 17))
            }
            OriginalAboutGrayFrame().frame(width: 200, height: 130).offset(x: 5, y: 67)
            OriginalText(text: state.heading, font: .chicago12)
                .frame(width: CGFloat((BitmapFont.chicago12?.width(state.heading) ?? 125) + 4), alignment: .leading)
                .background(.white).offset(x: 15, y: 60)
            ZStack(alignment: .topLeading) {
                if state.showsSystemInformation {
                    ForEach(Array(OriginalAboutRules.systemLabels.enumerated()), id: \.offset) { index, title in
                        OriginalText(text: title, font: .geneva9)
                            .offset(x: CGFloat(84 - (BitmapFont.geneva9?.width(title) ?? 0)), y: CGFloat(2 + index * 16))
                        if index < systemInformation.count {
                            OriginalText(text: systemInformation[index], font: .geneva9).offset(x: 90, y: CGFloat(2 + index * 16))
                        }
                    }
                } else {
                    ForEach(OriginalAboutRules.creditPositions(width: { BitmapFont.geneva9?.width($0) ?? 0 }), id: \.index) { position in
                        OriginalText(text: OriginalAboutRules.credits[position.index], font: .geneva9)
                            .offset(x: CGFloat(position.x), y: CGFloat(position.baseline - 10))
                    }
                }
            }.frame(width: 190, height: 115).clipped().offset(x: 10, y: 77)
            OriginalManagementButton(title: "OK", width: 80, isDefault: true, action: done)
                .offset(x: 270, y: 170).keyboardShortcut(.defaultAction)
        }.frame(width: 400, height: 200).clipped()
            .onReceive(Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()) { _ in
                pollAudio(state.showsSystemInformation)
            }
    }
}

/// A5−19a is qd.gray (24 bytes before qd.thePort). QuickDraw FrameRect
/// uses the port-anchored AA55 pattern; dialog origin(5,67) has even parity.
private struct OriginalAboutGrayFrame: View {
    var body: some View {
        Canvas { context, size in
            let w = Int(size.width), h = Int(size.height)
            guard w > 1, h > 1 else { return }
            for y in 0..<h {
                for x in 0..<w where (x == 0 || y == 0 || x == w-1 || y == h-1) && (x+y).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black))
                }
            }
        }
    }
}
