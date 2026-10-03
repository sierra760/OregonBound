import SwiftUI

struct OriginalOutfittingView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var quantities = Array(repeating: "", count: 7)
    private let labels = ["Oxen", "Sets of Clothing", "Boxes of Bullets (20/box)", "Spare Wagon Wheels", "Spare Wagon Axles", "Spare Wagon Tongues", "Pounds of Food"]
    private let maxima = [20, 50, 99, 3, 3, 3, 2000]
    private let prices = [2000, 1000, 200, 1000, 1000, 1000, 20]
    private var total: Int { quantities.indices.reduce(0) { $0 + amount($1) * prices[$1] } }
    private func amount(_ i: Int) -> Int { min(9999, max(0, Int(quantities[i]) ?? 0)) }
    private func money(_ cents: Int) -> String { String(format: "%d.%02d", cents / 100, cents % 100) }

    var body: some View {
        if game.setupDialog == .buyingAdvice {
            OriginalTextDialogView(resource: 9031, proceed: game.setupDialogAction(for: .buyingAdvice))
        }
        else {
            OriginalWindow {
                ZStack(alignment: .topLeading) {
                    PixelArtwork(resource: 19030, monochromeResource: 9030).frame(width: 494, height: 304)
                    label("Matt’s General Store", x: 168, y: 94, width: 321, font: .bold14, alignment: .center)
                    label("Max", x: 168, y: 120, width: 33, font: .bold12, alignment: .trailing)
                    label("Buy", x: 207, y: 120, width: 31, font: .bold12)
                    label("Item", x: 242, y: 120, width: 126, font: .bold12)
                    label("Unit Price", x: 370, y: 120, width: 63, font: .bold12, alignment: .trailing)
                    label("Cost", x: 435, y: 121, width: 51, font: .bold12, alignment: .trailing)
                    ForEach(quantities.indices, id: \.self) { i in
                        label(String(maxima[i]), x: 168, y: 137 + i * 18, width: 33, alignment: .trailing)
                        OriginalTextEntry(label: labels[i], text: $quantities[i], font: .plain12)
                            .frame(width: 29, height: 13).offset(x: 207, y: CGFloat(137 + i * 18))
                            .onChange(of: quantities[i]) { value in
                                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(OriginalStoreRules.inputDigits[i]))
                                if quantities[i] != digits { quantities[i] = digits }
                            }
                        label(labels[i], x: 242, y: 137 + i * 18, width: 126)
                        label((i == 0 ? "$" : "") + money(prices[i]), x: 370, y: 137 + i * 18, width: 62, alignment: .trailing)
                        label((i == 0 ? "$" : "") + money(amount(i) * prices[i]), x: 435, y: 137 + i * 18, width: 52, alignment: .trailing)
                    }
                    label("Total:", x: 395, y: 265, width: 37, font: .bold12)
                    label("$" + money(total), x: 435, y: 263, width: 52, alignment: .trailing)
                    label("You have \(dollars(trip.cash))", x: 329, y: 287, width: 158, font: .bold12, alignment: .trailing)
                    OriginalButton(title: "Help") { game.presentSetupDialog(.buyingAdvice) }.frame(width: 60, height: 20).offset(x: 171, y: 278)
                    OriginalButton(title: "Buy", action: purchase).frame(width: 60, height: 20).offset(x: 245, y: 278)
                }
            }
        }
    }
    private func label(_ text: String, x: Int, y: Int, width: Int, font: BitmapFont? = .plain12, alignment: Alignment = .leading) -> some View {
        OriginalText(text: text, font: font).frame(width: CGFloat(width), alignment: alignment).offset(x: CGFloat(x), y: CGFloat(y))
    }
    private func purchase() {
        let cart = Dictionary(uniqueKeysWithValues: Supply.allCases.enumerated().map { i, item in
            (item, amount(i) * (item == .bullets ? 20 : 1))
        })
        game.perform { try JourneyEngine.completeOutfitting(cart, in: &$0) }
    }
}
