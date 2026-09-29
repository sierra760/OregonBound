import Foundation

/// CODE3:2220 pane selection and CODE18:0f44–1164 custom loss drawing.
struct OriginalRiverResultContent {
    enum HeadingFont { case plain12, bold14 }
    struct Run: Equatable {
        let text: String
        let x: Int
        let y: Int
    }
    let isFailure: Bool
    let heading: String
    let headingFont: HeadingFont
    let lossRuns: [Run]

    init(outcome: OriginalRiverRules.Outcome, names: [String]) {
        isFailure = outcome.status == 1 || outcome.status == 2
        headingFont = isFailure ? .plain12 : .bold14
        let text = OriginalResources.strings(3021)
        if !isFailure {
            let index = outcome.status == 3 ? 1 : outcome.status == 4 ? 2 : 0
            heading = text[index] + "." // DITL6320's authored ^0. template.
            lossRuns = []
            return
        }
        // Original DITL6330 intentionally uses this title for BOTH failures.
        heading = "Your wagon tipped over while crossing the river."
        if outcome.losses.allSatisfy({ $0 == 0 }), outcome.drownedMembers.isEmpty {
            lossRuns = [.init(text: text[4], x: 10, y: 30), .init(text: text[5], x: 10, y: 42)]
            return
        }
        var runs = [Run(text: text[6], x: 10, y: 30)]
        let nouns = OriginalResources.strings(3011)
        var row = 0
        func append(_ value: String) {
            runs.append(.init(text: value, x: 60, y: 30 + row * 12))
            row += 1
        }
        for (index, raw) in outcome.losses.enumerated() where raw > 0 {
            let count = index == 0 ? (raw + 1) / 2 : raw
            append(OriginalJournalRules.number(count) + " " + nouns[index + (count == 1 ? 7 : 0)])
        }
        if outcome.drownedMembers.contains(0) {
            append(OriginalResources.strings(1522)[24])
        } else {
            // Original walks the five slot flags, not their native array order.
            for index in 1..<max(1, min(5, names.count)) where outcome.drownedMembers.contains(index) {
                append(names[index] + text[7])
            }
        }
        lossRuns = runs
    }
}
