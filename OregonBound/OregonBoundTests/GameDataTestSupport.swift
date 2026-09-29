import XCTest
@testable import OregonBound

/// The test bundle ships no MECC or Apple assets. Tests read the same imported
/// data folder as the app (or the folder named by OREGON_BOUND_DATA), and the
/// reference screenshots stay outside the public repository.
enum GameDataTestSupport {
    static let missingMessage = "No imported game data: run the app once and import your original files, or set \(GameData.environmentOverride)."

    /// Skips the current test when the original files have not been imported.
    static func requireGameData() throws {
        try XCTSkipUnless(GameData.isReady, missingMessage)
    }

    /// Original screen captures used for pixel comparisons; skipped when absent.
    static func referenceCapture(named name: String, withExtension ext: String) throws -> URL {
        if let url = Bundle(for: Marker.self).url(forResource: name, withExtension: ext) { return url }
        throw XCTSkip("Reference capture \(name).\(ext) is not bundled with this checkout.")
    }
    private final class Marker {}
}
