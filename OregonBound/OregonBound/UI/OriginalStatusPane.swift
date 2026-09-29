import SwiftUI

/// DITL 6183 and CODE3:2e00,2f84,340c. All coordinates are original pixels.
struct OriginalStatusPane: View {
    let trip: Journey
    private let font = BitmapFont.plain12
    var body: some View {
        ZStack(alignment: .topLeading) {
            OriginalDialogContents(resource: 6183, font: .plain12) { _ in }
            ForEach(Array(Supply.allCases.enumerated()), id: \.element.id) { index, supply in
                let count = trip.displayQuantity(supply)
                let labels = OriginalResources.strings(3011)
                let labelIndex = index + (count == 1 ? 7 : 0)
                line(String(count), x: 1, baseline: 61 + index * 14, width: 50, alignment: .trailing)
                line(labels.indices.contains(labelIndex) ? labels[labelIndex] : supply.title,
                     x: 57, baseline: 61 + index * 14)
            }
            // The original removes the cents suffix, including for a fractional balance.
            line("$" + (trip.cash / 100).formatted(.number.locale(Locale(identifier: "en_US"))),
                 x: 1, baseline: 159, width: 50, alignment: .trailing)
            line(OriginalResources.strings(3016).first ?? "money", x: 57, baseline: 159)
            health
            line("Occupation:", x: 1, baseline: 195, width: 130, alignment: .trailing)
            line(trip.profession.rawValue, x: 135, baseline: 195)
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
