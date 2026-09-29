/// CODE4:04fa–0770, DITL9010: the single-wagon List of Legends attract page.
enum OriginalLegendsRules {
    enum AttractPage: Equatable {
        case title, legends
        var durationTicks: Int { self == .title ? 7200 : 600 }
        var next: Self { self == .title ? .legends : .title }
    }
    struct Row: Identifiable, Equatable {
        let id: Int
        let rank: String
        let name: String
        let classification: String
        let points: String
    }
    static let emptyMessage = "There are no entries in the List of Legends."
    static let emptyMessageTop = 157 // baseline124 +3*15 -ascent12
    static func rowTop(_ index: Int) -> Int { 112 + index * 15 }

    /// These labels describe achieved points, independently of travel settings.
    static func classification(score: Int) -> String {
        ["Greenhorn", "Adventurer", "Trail Guide"][min(2, max(0, score / 3000))]
    }
    static func scoreText(_ score: Int) -> String {
        let digits = Array(String(max(0, score)))
        return digits.enumerated().map { index, character in
            String(character) + (index < digits.count - 1 && (digits.count - index - 1) % 3 == 0 ? "," : "")
        }.joined()
    }
    /// Table insertion/order is owned by OriginalEndingPresentation. This only
    /// formats the supplied table; passing [] preserves the original empty state.
    static func rows(_ legends: [OriginalEndingPresentation.Legend]) -> [Row] {
        legends.prefix(10).enumerated().map { index, legend in
            .init(id: index, rank: "\(index + 1).", name: legend.name,
                  classification: classification(score: legend.score), points: scoreText(legend.score))
        }
    }
}
