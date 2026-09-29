import SwiftUI

/// The 262×199 trail-pane dialogs DITL 6030/6050 and their help/response pages.
struct OriginalChoicePane: View {
    @ObservedObject var game: GameController
    let trip: Journey
    let panel: GamePanel
    @State private var help = false
    @State private var alreadySelected = false
    private var isPace: Bool { panel == .pace }
    private var resource: Int { isPace ? 6050 : 6030 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
            originalPaper
            OriginalText(text: isPace ? "How fast do you want to travel?" : "How much do you want to eat?", width: 243)
                .offset(x: 11, y: 9)
            ForEach(0..<3) { index in
                OriginalIconChoice(icon: resource + index, title: title(index), width: 185) { choose(index) }
                    .offset(x: 13, y: CGFloat(44 + index * 51))
            }
            OriginalIconChoice(icon: 9999, title: "", width: 42) { help = true }
                .accessibilityLabel("Help").offset(x: 202, y: 95)
            }.allowsHitTesting(!help && !alreadySelected).accessibilityHidden(help || alreadySelected)
            if help {
                OriginalDialogContents(resource: isPace ? 6060 : 6040) { _ in help = false }
            }
            if alreadySelected {
                OriginalDialogContents(resource: resource + 1,
                                       substitutions: [isPace ? trip.pace.rawValue.lowercased() : trip.rations.rawValue.lowercased()]) { _ in
                    alreadySelected = false
                    game.panel = nil
                }
            }
        }
    }
    private func title(_ index: Int) -> String {
        isPace ? ["A steady pace", "A strenuous pace", "A grueling pace"][index] : ["Filling", "Meager", "Bare bones"][index]
    }
    private func choose(_ index: Int) {
        if (isPace ? Int(trip.pace.originalIndex) : Int(trip.rations.originalIndex)) == index {
            alreadySelected = true
        } else {
            game.perform {
                if isPace {
                    $0.pace = Pace.allCases[index]
                    $0.record(OriginalJournalRules.decision(.pace(index)))
                } else {
                    $0.rations = Rations.allCases[index]
                    $0.record(OriginalJournalRules.rations(index))
                }
            }
            game.panel = nil
        }
    }
}

struct OriginalIconChoice: View {
    let icon: Int
    let title: String
    let width: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    PixelArtwork(resource: 10129).frame(width: 42, height: 46)
                    PixelArtwork(resource: icon).frame(width: 32, height: 32)
                }
                if !title.isEmpty { OriginalText(text: title) }
            }.frame(width: width, height: 46, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
