import Foundation
import Testing
@testable import OregonBound

struct RuntimeResourceTests {
    @Test func extractsOnlySuppliedResourcesAndRejectsMissingInput() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        // Thirteen synthetic scripts, each containing only the end opcode.
        let script = Data([0, 13] + Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 6, 2, 255), count: 13).flatMap { $0 })
        var cursor = Data(repeating: 0, count: 68)
        cursor[0] = 128
        cursor[32] = 192
        let fork = MacResourceFork(resources: [
            MacResource(type: "Scpt", id: 5310, name: nil, attributes: 0, data: script),
            MacResource(type: "CURS", id: 128, name: nil, attributes: 0, data: cursor)
        ])
        let output = ExtractionOutput(root: destination)
        try RuntimeResourceExtractor.extract(trailFork: fork, into: output)
        #expect(try Data(contentsOf: output.url("runtime/scpt_5310.bin")) == script)
        #expect(try Data(contentsOf: output.url("runtime/curs_128.bin")) == cursor)
        #expect(Array(OriginalHuntCursor.decode(cursor).prefix(12)) == [0,0,0,255,255,255,255,255,0,0,0,0])
        #expect(throws: RuntimeResourceExtractor.Failure.self) {
            try RuntimeResourceExtractor.extract(trailFork: MacResourceFork(resources: []), into: output)
        }
    }

    @Test func aboutIdentifiesTheIndependentApp() {
        #expect(OriginalAboutRules.program == "Oregon Bound")
        #expect(OriginalAboutRules.copyright == "Copyright 2026 Sierra Burkhart")
        #expect(OriginalAboutRules.State().heading == "Original game team:")
        #expect(OriginalAboutRules.attribution.contains("Not affiliated or endorsed."))
    }
}
