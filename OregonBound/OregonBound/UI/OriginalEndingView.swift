import SwiftUI

/// CODE10 ending sequence: full arrival artwork, then DITL9100/9130.
/// A lost party uses DITL9150 and Imag19150.
struct OriginalEndingView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var name: String

    init(game: GameController, trip: Journey) {
        self.game = game; self.trip = trip
        _name = State(initialValue: trip.members.first?.name ?? "")
    }
    private var qualifies: Bool {
        OriginalEndingPresentation.insertionIndex(score: JourneyEngine.score(trip),
            legends: game.legends.filter { $0.id != trip.id.uuidString }) != nil
    }
    var body: some View {
        OriginalWindow {
            ZStack(alignment: .topLeading) {
                originalPaper
                if !trip.won {
                    OriginalDialogContents(resource: 9150) { _ in game.mainMenu() }
                    PixelArtwork(resource: 19150, monochromeResource: 9150).frame(width: 262, height: 155).offset(x: 111, y: 10)
                    Rectangle().strokeBorder(.black, lineWidth: 1).frame(width: 264, height: 157).offset(x: 110, y: 9)
                } else if trip.originalEndingStage == .score || trip.originalEndingStage == .completed {
                    OriginalDialogContents(resource: qualifies ? 9100 : 9130, substitutions: [trip.dateText]) { _ in
                        game.submitOriginalScore(name: name)
                    }
                    OriginalScoreBreakdown(trip: trip)
                    if qualifies {
                        OriginalTextEntry(label: "Name for the List of Legends", text: $name)
                            .frame(width: 190, height: 15).offset(x: 185, y: 276)
                            .onChange(of: name) { value in if value.count > 26 { name = String(value.prefix(26)) } }
                    }
                } else {
                    PixelArtwork(resource: 19090, monochromeResource: 9090).frame(width: 494, height: 304)
                    OriginalButton(title: "Continue") { game.showOriginalScore() }
                        .frame(width: 80, height: 20).offset(x: 373, y: 270)
                }
            }
        }
    }
}

struct OriginalScoreBreakdown: View {
    let trip: Journey
    private var rows: [OriginalEndingPresentation.Row] {
        OriginalEndingPresentation.rows(trip, strings: OriginalResources.strings(3004))
    }
    private var extraRowHeight: Int { trip.gameEdition == .macintoshCD12 ? 12 : 0 }
    private var subtotal: Int { rows.reduce(0) { $0 + $1.points } }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows) { row in
                right(row.label, edge: 340, y: 65 + row.id * 12)
                right(String(row.points), edge: 400, y: 65 + row.id * 12)
            }
            OriginalText(text: "+", font: .bold12).offset(x: 346, y: CGFloat(149 + extraRowHeight))
            Rectangle().frame(width: 54, height: 1).offset(x: 346, y: CGFloat(161 + extraRowHeight))
            right(String(subtotal), edge: 400, y: 163 + extraRowHeight)
            right(trip.profession.rawValue + " bonus", edge: 340, y: 177 + extraRowHeight)
            right(trip.profession.scoreMultiplierText, edge: 400, y: 177 + extraRowHeight)
            OriginalText(text: "x", font: .bold12).offset(x: 346, y: CGFloat(177 + extraRowHeight))
            Rectangle().frame(width: 54, height: 1).offset(x: 346, y: CGFloat(189 + extraRowHeight))
            right("Your Score = ", edge: 340, y: 191 + extraRowHeight)
            right(String(JourneyEngine.score(trip)), edge: 400, y: 191 + extraRowHeight)
        }
    }
    private func right(_ text: String, edge: CGFloat, y: Int) -> some View {
        OriginalText(text: text, font: .bold12)
            .frame(width: edge, alignment: .trailing).offset(y: CGFloat(y))
    }
}
