import Foundation
import Testing
@testable import OregonBound

struct OriginalEndingReportTests {
    @Test func arrivalAndLossKeepAuthoredText() throws {
        #expect(try OriginalTrailLogExport.data(records: OriginalEndingReport.arrival(won: true)) ==
            Data("You made it to the Willamette Valley.\r".utf8))
        #expect(OriginalEndingReport.arrival(won: false).isEmpty)
    }
    @Test func scoreExportsSummaryWithoutDateNameOrBreakdown() throws {
        let records = OriginalEndingReport.score(survivors: 1, health: "Very Poor", score: 123)
        #expect(records.count == 3)
        #expect(records.map(\.appendCarriageReturn) == [true, false, true])
        #expect(try OriginalTrailLogExport.data(records: records) ==
            Data("1 person arrived in very poor health.\rYour Score = 123\r".utf8))
        let plural = OriginalEndingReport.score(survivors: 5, health: "Good", score: 5011)
        #expect(plural.first?.text == "5 people arrived in good health.")
        #expect(OriginalEndingReport.score(survivors: 0, health: "ÉGOOD", score: 0).first?.text ==
            "0 people arrived in Égood health.")
    }
    @Test func rawFragmentsDoNotWrapUntilCRIsRequested() throws {
        let text = String(repeating: "x", count: 255)
        #expect(try OriginalTrailLogExport.data(records: [.init(text: text)]).isEmpty)
        #expect(try OriginalTrailLogExport.data(records: [.init(text: text, appendCarriageReturn: false)]) == Data(text.utf8))
    }
    @Test func scoreLabelAndNumberRetainSeparateTrimBoundaries() throws {
        // 126*251 + 362 =31988. The score label brings the buffer to32001,
        // so the next append trims8 complete hard lines before adding the number.
        var records = Array(repeating: OriginalTrailLogExport.Record(text: String(repeating: "x", count: 250)), count: 126)
        records += [.init(text: String(repeating: "y", count: 180)), .init(text: String(repeating: "z", count: 180))]
        #expect(try OriginalTrailLogExport.data(records: records).count == 31_988)
        records += [.init(text: "Your Score = ", appendCarriageReturn: false), .init(text: "123")]
        let data = try OriginalTrailLogExport.data(records: records)
        #expect(data.count == 32_001 - 8 * 251 + 4)
        #expect(data.suffix(17) == Data("Your Score = 123\r".utf8))
    }
}
