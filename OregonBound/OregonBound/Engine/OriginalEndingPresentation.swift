import Foundation

enum OriginalEndingStage: String, Codable { case arrival, score, completed }

/// CODE10:035c–0c86, CODE3:1bd6, and the single-wagon CONF1000 table.
enum OriginalEndingPresentation {
    struct Legend: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let score: Int
    }
    static let initialLegends: [Legend] = zip(
        ["Stephen Meek", "David Hastings", "Andrew Sublette", "Celinda Hines", "Ezra Meeker",
         "William Vaughn", "Mary Bartlett", "William Wiggins", "Charles Hopper", "Elijah White"],
        [7650, 5694, 4138, 2945, 2052, 1401, 937, 615, 396, 250]
    ).enumerated().map { .init(id: "original-\($0.offset)", name: $0.element.0, score: $0.element.1) }

    /// Ties follow existing entries. A full table requires a strictly higher score.
    static func insertionIndex(score: Int, legends: [Legend]) -> Int? {
        guard score > 0 else { return nil }
        if let index = legends.firstIndex(where: { score > $0.score }) { return index }
        return legends.count < 10 ? legends.count : nil
    }
    static func legends(with scores: [HighScore], excluding id: UUID? = nil) -> [Legend] {
        var result = initialLegends
        for entry in scores where entry.id != id {
            if let index = insertionIndex(score: entry.score, legends: result) {
                result.insert(.init(id: entry.id.uuidString, name: entry.name, score: entry.score), at: index)
                result = Array(result.prefix(10))
            }
        }
        return result
    }

    struct Row: Equatable, Identifiable {
        let id: Int
        let label: String
        let points: Int
    }
    static func rows(_ trip: Journey, strings: [String]) -> [Row] {
        guard trip.won, strings.count >= 24 else { return [] }
        let survivors = trip.livingMembers.count
        let perPerson = OriginalHealth.scorePerSurvivor(badness: trip.healthBadness)
        let oxen = trip.displayQuantity(.oxen)
        let parts = trip.inventory[.wheels] + trip.inventory[.axles] + trip.inventory[.tongues]
        let clothing = trip.inventory[.clothing]
        let bullets = trip.inventory[.bullets]
        let food = trip.inventory[.food]
        let counts = [survivors, 1, oxen, parts, clothing, bullets, food, trip.cash / 100]
        let bases = [10, 4, 11, 12, 13, 14, 15, 16]
        let divisors = [perPerson, 50, 4, 2, 2, 50, 25, 5]
        let points = JourneyEngine.scoreLines(trip).map(\.points)
        return counts.indices.map { index in
            let singular = index == 7 ? trip.cash == 1 : counts[index] == 1
            let resourceIndex = bases[index] + (index != 1 && singular ? 7 : 0)
            let label = "\(counts[index])" + strings[resourceIndex]
                .replacingOccurrences(of: "^0", with: trip.healthLabel.lowercased())
                .replacingOccurrences(of: "^1", with: "\(divisors[index])")
            return Row(id: index, label: label, points: points[index])
        }
    }
}
