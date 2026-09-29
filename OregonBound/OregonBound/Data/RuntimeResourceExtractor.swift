import Foundation

/// Resources interpreted at runtime, stored only in the player's imported data.
enum RuntimeResourceExtractor {
    enum Failure: Error { case missingOrInvalidResource(String) }

    static func extract(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        guard let script = trailFork["Scpt", 5310]?.data,
              let programs = try? OriginalRiverAnimation.decode(script), programs.count == 13 else {
            throw Failure.missingOrInvalidResource("Scpt 5310")
        }
        guard let cursor = trailFork["CURS", 128]?.data, cursor.count == 68 else {
            throw Failure.missingOrInvalidResource("CURS 128")
        }
        try output.write(script, to: "runtime/scpt_5310.bin")
        try output.write(cursor, to: "runtime/curs_128.bin")
    }
}
