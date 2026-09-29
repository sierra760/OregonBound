import SwiftUI

/// DITL 5220/5221, shown beneath the 77-pixel traveling landscape.
struct OriginalRestPane: View {
    @ObservedObject var game: GameController
    @State private var days = ""
    @State private var invalid = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            OriginalText(text: "How long do you want to rest?", width: 229).offset(x: 11, y: 7)
            OriginalTextEntry(label: "Days to rest", text: $days)
                .frame(width: 30, height: 15).offset(x: 91, y: 45)
            Rectangle().stroke(.black, lineWidth: 1).frame(width: 38, height: 21).offset(x: 87, y: 41)
                .allowsHitTesting(false)
            OriginalText(text: "day(s)").offset(x: 130, y: 45)
            OriginalButton(title: "Cancel") { game.panel = nil }
                .frame(width: 70, height: 20).offset(x: 40, y: 90).keyboardShortcut(.cancelAction)
            OriginalButton(title: "OK", isDefault: true) {
                guard let count = Int(days), (1...9).contains(count) else { invalid = true; return }
                game.perform { try JourneyEngine.beginRest(days: count, in: &$0) }
                game.panel = nil
            }.frame(width: 70, height: 20).offset(x: 152, y: 90).keyboardShortcut(.defaultAction)
            if invalid { OriginalDialogContents(resource: 5221) { _ in invalid = false } }
        }
    }
}
