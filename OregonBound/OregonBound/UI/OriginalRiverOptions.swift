import SwiftUI

struct OriginalRiverOptions: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var help = false
    @State private var warning: Int?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
            originalPaper
            OriginalText(text: "You must cross the river to continue.  The river is currently \(trip.riverWidth) feet wide and \(String(format: "%.1f", trip.riverDepth)) feet deep.", width: 242)
                .offset(x: 10, y: 8)
            choice(.ford, icon: 8070, text: "Attempt to ford the river", y: 80)
            choice(.caulk, icon: 8071, text: "Caulk the wagon and float it", y: 135)
            if JourneyEngine.availableCrossings(in: trip).contains(.ferry) {
                choice(.ferry, icon: 8072, text: "Take a ferry for $5.00", y: 190)
            }
            if JourneyEngine.availableCrossings(in: trip).contains(.guide) {
                choice(.guide, icon: 8073, text: "Hire an Indian to help", y: 190)
            }
            Button { help = true } label: {
                ZStack {
                    PixelArtwork(resource: 10129).frame(width: 42, height: 46)
                    PixelArtwork(resource: 9999).frame(width: 32, height: 32)
                }
            }.buttonStyle(.plain).accessibilityLabel("River Crossing Help").offset(x: 192, y: 246)
            }.allowsHitTesting(!help && warning == nil).accessibilityHidden(help || warning != nil)
            if help {
                OriginalDialogContents(resource: 8075, hiddenItems: trip.locationID == "snake" ? [2] : [3]) { _ in help = false }
            }
            if let warning {
                OriginalDialogContents(resource: warning) { _ in self.warning = nil }
            }
        }
    }
    private func choice(_ method: CrossingMethod, icon: Int, text: String, y: Int) -> some View {
        Button { choose(method) } label: {
            HStack(spacing: 5) {
                ZStack {
                    PixelArtwork(resource: 10129).frame(width: 42, height: 46)
                    PixelArtwork(resource: icon).frame(width: 32, height: 32)
                }
                OriginalText(text: text)
            }.frame(width: 240, height: 46, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(text).offset(x: 13, y: CGFloat(y))
    }
    private func choose(_ method: CrossingMethod) {
        let dimensions = OriginalRiverRules.dimensions(in: trip)
        if OriginalRiverRules.rejection(method, destination: OriginalRiverRules.destinationIndex(trip),
            depthHalfFeet: Int(dimensions.depthHalfFeet), cash: trip.cash, clothing: trip.inventory[.clothing]) != nil {
            switch method {
            case .caulk: warning = 8071
            case .ferry: warning = dimensions.depthHalfFeet < 5 ? 8072 : 8073
            case .guide: warning = 8074
            case .ford: break
            }
        } else { game.crossRiver(method) }
    }
}
