import SwiftUI

/// DITL6270,6280,6281. Control icons come from CNTL refCon, not CNTL ID.
struct OriginalRoutePane: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var insufficientToll = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            Group {
                OriginalText(text: "The trail divides here.  Which way do you want to go?", width: 247)
                    .offset(x: 11, y: 9)
                if trip.locationID == "south-pass" {
                    choice(icon: 6251, text: "Head to Fort Bridger\nto buy supplies", y: 62) { route("bridger") }
                    choice(icon: 6250, text: "Take the shortcut to\nthe Green River Crossing", y: 120) { route("green") }
                } else if trip.locationID == "blue-mountains" {
                    choice(icon: 6251, text: "Head to Fort Walla Walla\nto buy supplies", y: 62) { route("walla") }
                    choice(icon: 6252, text: "Take the shortcut to\nThe Dalles", y: 120) { route("dalles") }
                } else if trip.locationID == "dalles" {
                    choice(icon: 147, text: "Take the Barlow Toll Road", y: 62) {
                        guard trip.cash >= 500 else { insufficientToll = true; return }
                        game.perform { try JourneyEngine.takeBarlowRoad(&$0) }
                    }
                    choice(icon: 131, text: "Raft down the river", y: 120) {
                        game.perform { try JourneyEngine.beginRaft(&$0) }
                    }
                }
            }.allowsHitTesting(!insufficientToll).accessibilityHidden(insufficientToll)
            if insufficientToll {
                OriginalDialogContents(resource: 6191) { _ in insufficientToll = false }
            }
        }.frame(width: 262, height: 199)
    }
    private func choice(icon: Int, text: String, y: CGFloat, action: @escaping () -> Void) -> some View {
        OriginalIconChoice(icon: icon, title: text, width: 242, action: action).offset(x: 13, y: y)
    }
    private func route(_ destination: String) { game.perform { try JourneyEngine.chooseRoute(destination, in: &$0) } }
}
