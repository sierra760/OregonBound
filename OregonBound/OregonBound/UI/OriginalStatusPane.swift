import SwiftUI

/// DITL 6183 and CODE3:2e00,2f84,340c. All coordinates are original pixels.
struct OriginalStatusPane: View {
    let trip: Journey
    private let font = BitmapFont.plain12
    var body: some View {
        ZStack(alignment: .topLeading) {
            OriginalDialogContents(resource: 6183, font: .plain12) { _ in }
            ForEach(Self.supplyRows(trip, strings: OriginalResources.strings(Self.supplyStringsID(for: trip.gameEdition)))) { row in
                line(String(row.count), x: 1, baseline: 61 + row.id * 14, width: 50, alignment: .trailing)
                line(row.label, x: 57, baseline: 61 + row.id * 14)
            }
            // The original removes the cents suffix, including for a fractional balance.
            line("$" + (trip.cash / 100).formatted(.number.locale(Locale(identifier: "en_US"))),
                 x: 1, baseline: Self.moneyBaseline(for: trip.gameEdition), width: 50, alignment: .trailing)
            line(OriginalResources.strings(3016).first ?? "money", x: 57, baseline: Self.moneyBaseline(for: trip.gameEdition))
            health
            line("Occupation:", x: 1, baseline: 195, width: 130, alignment: .trailing)
            line(trip.profession.rawValue, x: 135, baseline: 195)
        }
    }
    struct SupplyRow: Identifiable {
        let id: Int
        let count: Int
        let label: String
    }
    static func supplyStringsID(for edition: GameEdition) -> Int { edition == .macintoshCD12 ? 3030 : 3011 }
    static func moneyBaseline(for edition: GameEdition) -> Int { 61 + Inventory.itemCount(for: edition) * 14 }
    static func supplyRows(_ trip: Journey, strings: [String]) -> [SupplyRow] {
        let itemCount = Inventory.itemCount(for: trip.gameEdition)
        return (0..<itemCount).map { index in
            let count = index == 7 ? trip.inventory.perishableFood : trip.displayQuantity(Supply.allCases[index])
            let labelIndex = index + (count == 1 ? itemCount : 0)
            let fallback = index == 7 ? "pounds of perishable food" : Supply.allCases[index].title
            return SupplyRow(id: index, count: count, label: strings.indices.contains(labelIndex) ? strings[labelIndex] : fallback)
        }
    }
    private var healthRows: [(member: PartyMember, baseline: Int, longName: Bool)] {
        var baseline = 61
        return trip.members.map { member in
            let longName = (font?.width(member.name) ?? 0) > 49
            defer { baseline += longName ? 28 : 14 }
            return (member, baseline - 45, longName)
        }
    }
    private var health: some View {
        ZStack(alignment: .topLeading) {
            ForEach(healthRows, id: \.member.id) { row in
                if row.longName { line(row.member.name, x: 0, baseline: row.baseline) }
                line((row.longName ? "" : row.member.name) + " –", x: 0,
                     baseline: row.baseline + (row.longName ? 14 : 0), width: 59, alignment: .trailing)
                line(row.member.alive ? (row.member.illness ?? trip.healthLabel) : "Deceased", x: 59,
                     baseline: row.baseline + (row.longName ? 14 : 0))
            }
        }.frame(width: 119, height: 133, alignment: .topLeading)
            .clipped().offset(x: 142, y: 45)
    }
    private func line(_ text: String, x: Int, baseline: Int, width: Int? = nil,
                      alignment: Alignment = .leading) -> some View {
        OriginalText(text: text, font: font)
            .frame(width: width.map(CGFloat.init), alignment: alignment)
            .offset(x: CGFloat(x), y: CGFloat(baseline - (font?.metrics.header.ascent ?? 9)))
    }
}
