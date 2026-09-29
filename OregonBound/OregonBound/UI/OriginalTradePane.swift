import SwiftUI

/// CODE3 trading request DITL6120/6121, then offer DITL6310. The saved session
/// owns every random result; this view never generates an offer during rendering.
struct OriginalTradePane: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var selectedItem = 0
    @State private var quantity = ""
    @State private var validationError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            Group {
                if let session = trip.originalTradeSession {
                    if session.isValid { offerPane(session) }
                    else { invalidSavedOffer }
                } else { requestPane }
            }.allowsHitTesting(validationError == nil).accessibilityHidden(validationError != nil)
            if let validationError {
                OriginalDialogContents(resource: 6290, substitutions: [validationError]) { _ in self.validationError = nil }
            }
        }.frame(width: 262, height: 199).clipped()
    }

    private var requestPane: some View {
        ZStack(alignment: .topLeading) {
            OriginalText(text: "What do you want to get by trading?", font: .bold14, width: 258).offset(x: 2, y: 3)
            OriginalText(text: "Number:", font: .bold14).offset(x: 4, y: 72)
            OriginalTextEntry(label: "Number to receive", text: $quantity, font: .bold14)
                .frame(width: 32, height: 16).offset(x: 68, y: 73).onSubmit(submit)
            Rectangle().strokeBorder(.black, lineWidth: 1).frame(width: 36, height: 20)
                .offset(x: 66, y: 71).allowsHitTesting(false)
            ForEach(0..<8) { item in
                OriginalSystemRadio(title: Self.radioLabels[item], selected: selectedItem == item,
                                    width: 134, height: 18, paper: originalPaper) {
                    selectedItem = item
                }.offset(x: 112, y: CGFloat(24 + item * 17))
            }
            OriginalButton(title: "Cancel") { game.panel = nil }
                .frame(width: 80, height: 20).offset(x: 25, y: 170).keyboardShortcut(.cancelAction)
            OriginalButton(title: "OK", isDefault: true, action: submit)
                .frame(width: 80, height: 20).offset(x: 149, y: 170).keyboardShortcut(.defaultAction)
        }.frame(width: 262, height: 199, alignment: .topLeading)
    }

    @ViewBuilder private func offerPane(_ session: OriginalTradingRules.Session) -> some View {
        if session.offer == nil {
            // Original no-offer pane hides Yes/No and dismisses via the pane.
            Button { finish(false) } label: { offerContents(session).contentShape(Rectangle()) }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .accessibilityLabel(message(session) + " Continue.")
        } else {
            ZStack(alignment: .topLeading) {
                offerContents(session)
                OriginalButton(title: "No") { finish(false) }
                    .frame(width: 60, height: 20).offset(x: 168, y: 122).keyboardShortcut(.cancelAction)
                OriginalButton(title: "Yes") { finish(true) }
                    .frame(width: 60, height: 20).offset(x: 168, y: 92).keyboardShortcut(.defaultAction)
                if let offer = session.offer {
                    OriginalText(text: "(You have \(available(offer.item)).)", font: .plain12, width: 108)
                        .frame(width: 108, height: 24, alignment: .topLeading).clipped().offset(x: 148, y: 153)
                }
            }.frame(width: 262, height: 199, alignment: .topLeading)
        }
    }

    private func offerContents(_ session: OriginalTradingRules.Session) -> some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            PixelArtwork(resource: 16080, frame: session.portrait).frame(width: 154, height: 199)
            // Imag16080 frame9 is108px wide; preserve its native pixels.
            PixelArtwork(resource: 16080, frame: 9).frame(width: 108, height: 199).offset(x: 154)
            OriginalText(text: message(session), font: .plain12, width: 104)
                .frame(width: 104, height: 168, alignment: .topLeading).clipped().offset(x: 146, y: 16)
        }.frame(width: 262, height: 199, alignment: .topLeading)
    }

    private var invalidSavedOffer: some View {
        OriginalDialogContents(resource: 6290, substitutions: ["The saved trade offer is invalid."]) { _ in
            game.perform { $0.originalTradeSession = nil }
            game.panel = nil
        }
    }
    private func message(_ session: OriginalTradingRules.Session) -> String {
        let request = OriginalTradingRules.description(item: session.request.item, quantity: session.request.quantity)
        guard let offer = session.offer else { return "Sorry, but nobody here’s got \(request) to spare." }
        return "Sure, I’ll trade you \(request) for \(OriginalTradingRules.description(item: offer.item, quantity: offer.quantity)). Is it a deal?"
    }
    private func available(_ item: Int) -> String {
        if item == 7 { return "$\(trip.cash / 100)" }
        let raw = trip.inventory[Supply.allCases[item]]
        return "\(item == 0 ? raw / 2 : raw)"
    }
    private func submit() {
        guard let count = Int(quantity) else { validationError = "You must enter a quantity for that item."; return }
        game.perform { trip in
            do { try OriginalTradingRules.begin(item: selectedItem, displayedQuantity: count, in: &trip) }
            catch { validationError = error.localizedDescription }
        }
    }
    private func finish(_ accept: Bool) {
        game.perform { try OriginalTradingRules.finish(accept: accept, in: &$0) }
        if game.trip?.originalTradeSession == nil { game.panel = nil }
    }
    private static let radioLabels = ["ox(en)", "set(s) of clothing", "bullets", "wagon wheel(s)", "wagon axle(s)",
                                      "wagon tongue(s)", "pounds of food", "$ (dollars cash)"]
}
