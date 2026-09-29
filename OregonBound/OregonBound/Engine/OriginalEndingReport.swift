/// Retained TextEdit append operations in the single-wagon CODE10 ending.
/// Journal-pane teardown precedes these; neither dates nor legend names are added here.
enum OriginalEndingReport {
    static func arrival(won: Bool) -> [OriginalTrailLogExport.Record] {
        won ? [.init(text: "You made it to the Willamette Valley.")] : []
    }

    /// CODE10:0c34–0c5e. Keep the score label and number as separate appends:
    /// CODE11 checks the existing buffer length before EACH operation.
    static func score(survivors: Int, health: String, score: Int) -> [OriginalTrailLogExport.Record] {
        let noun = survivors == 1 ? "person" : "people"
        // CODE10:04ee–0536 converts ASCII A...Z only, not all Unicode capitals.
        let lowered = String(String.UnicodeScalarView(health.unicodeScalars.map {
            (65...90).contains($0.value) ? UnicodeScalar($0.value + 32)! : $0
        }))
        return [
            .init(text: "\(survivors) \(noun) arrived in \(lowered) health."),
            .init(text: "Your Score = ", appendCarriageReturn: false),
            .init(text: String(score))
        ]
    }
}
