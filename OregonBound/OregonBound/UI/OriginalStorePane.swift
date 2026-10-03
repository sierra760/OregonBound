import SwiftUI

/// The 494×304 DITL9030 store pane, placed inside OriginalWindow. This is
/// CODE7's later store: Have column, Cancel instead of Help, seven-row cart.
struct OriginalStorePane: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var quantities = Array(repeating: "", count: 7)
    @State private var rejection: OriginalStoreRules.Rejection?
    private let labels = ["Oxen", "Sets of Clothing", "Boxes of Bullets (20/box)", "Spare Wagon Wheels",
                          "Spare Wagon Axles", "Spare Wagon Tongues", "Pounds of Food"]
    private var amounts: [Int] { quantities.map { Int($0) ?? 0 } }
    private var costs: [Int] { (0..<7).map { OriginalStoreRules.rowCost(item: $0, count: amounts[$0], in: trip) } }
    private func money(_ cents: Int) -> String { OriginalStoreRules.money(cents) }
    // Only the five regional 256-color CD images contain the fixed table text.
    // Matt's, classic, 16-color and monochrome backgrounds have empty cells.
    private var artworkContainsTableText: Bool {
        trip.edition == .macintoshCD12 && OriginalResources.colorMode == .color256 &&
        (19031...19035).contains(OriginalStoreRules.artworkResource(in: trip))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                PixelArtwork(resource: OriginalStoreRules.artworkResource(in: trip),
                             monochromeResource: OriginalStoreRules.artworkResource(in: trip) - 10000,
                             preserveDimensions: trip.edition == .macintoshCD12)
                    .frame(width: 494, height: 304, alignment: .topLeading)
                label(OriginalStoreRules.storeName(in: trip), x: 168, y: 94, width: 321, font: .bold14, alignment: .center)
                label("Have", x: 168, y: 120, width: 33, font: .bold12, alignment: .trailing)
                label("Buy", x: 207, y: 120, width: 31, font: .bold12, embeddedInArtwork: true)
                label("Item", x: 242, y: 120, width: 126, font: .bold12, embeddedInArtwork: true)
                label("Unit Price", x: 370, y: 120, width: 63, font: .bold12, alignment: .trailing, embeddedInArtwork: true)
                label("Cost", x: 435, y: 121, width: 51, font: .bold12, alignment: .trailing, embeddedInArtwork: true)
                ForEach(0..<7) { item in
                    label(String(OriginalStoreRules.have(in: trip)[item]), x: 168, y: 137 + item * 18, width: 33, alignment: .trailing)
                    OriginalTextEntry(label: labels[item], text: $quantities[item], font: .plain12)
                        .frame(width: 29, height: 13).offset(x: 207, y: CGFloat(137 + item * 18))
                        .onChange(of: quantities[item]) { value in
                            let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(OriginalStoreRules.inputDigits[item]))
                            if quantities[item] != digits { quantities[item] = digits }
                        }
                    label(labels[item], x: 242, y: 137 + item * 18, width: 126, embeddedInArtwork: true)
                    label((item == 0 ? "$" : "") + money(OriginalStoreRules.rowCost(item: item, count: 1, in: trip)),
                          x: 370, y: 137 + item * 18, width: 62, alignment: .trailing)
                    label((item == 0 ? "$" : "") + money(costs[item]), x: 435, y: 137 + item * 18, width: 52, alignment: .trailing)
                }
                label("Total:", x: 395, y: 265, width: 37, font: .bold12, embeddedInArtwork: true)
                label("$" + money(costs.reduce(0, +)), x: 435, y: 263, width: 52, alignment: .trailing)
                label("You have $" + money(trip.cash), x: 329, y: 287, width: 158, font: .bold12, alignment: .trailing)
                OriginalButton(title: "Cancel") { game.panel = nil }
                    .frame(width: 60, height: 20).offset(x: 171, y: 278).keyboardShortcut(.cancelAction)
                OriginalButton(title: "Buy", action: purchase)
                    .frame(width: 60, height: 20).offset(x: 245, y: 278).keyboardShortcut(.defaultAction)
            }.allowsHitTesting(rejection == nil).accessibilityHidden(rejection != nil)
            if let rejection {
                // DITL9032/9033/9034 have identical full-pane OK geometry.
                originalPaper
                OriginalText(text: rejection.errorDescription ?? "", font: .bold14, width: 476)
                    .offset(x: 6, y: rejection.dialogResource == 9034 ? 126 : 125)
                OriginalButton(title: "OK") { self.rejection = nil }
                    .frame(width: 80, height: 20).offset(x: 207, y: 269).keyboardShortcut(.defaultAction)
            }
        }.frame(width: 494, height: 304).clipped()
    }
    private func label(_ text: String, x: Int, y: Int, width: Int, font: BitmapFont? = .plain12,
                       alignment: Alignment = .leading, embeddedInArtwork: Bool = false) -> some View {
        Group {
            if embeddedInArtwork && artworkContainsTableText {
                // Keep the source pixels and expose their text to assistive tools.
                Color.clear.frame(height: CGFloat(font?.lineHeight ?? 14))
                    .accessibilityElement(children: .ignore).accessibilityLabel(text)
                    .accessibilityAddTraits(.isStaticText)
            } else {
                OriginalText(text: text, font: font)
            }
        }.frame(width: CGFloat(width), alignment: alignment)
         .offset(x: CGFloat(x), y: CGFloat(y))
    }
    private func purchase() {
        var purchased = false
        game.perform { trip in
            do { try OriginalStoreRules.buy(amounts, in: &trip); purchased = true }
            catch let error as OriginalStoreRules.Rejection { rejection = error }
            catch { game.error = error.localizedDescription }
        }
        if purchased { game.panel = nil }
    }
}
