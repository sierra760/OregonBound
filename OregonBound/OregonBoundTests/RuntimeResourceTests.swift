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

    @Test(arguments: [5000, 5800, 5210])
    func iconLookupDoesNotSelectSameNumberedArtwork(id: Int) {
        func entry(_ type: String, _ frame: Int = 0) -> ManifestImage {
            ManifestImage(resource: ManifestResource(source_file: "synthetic", type: type,
                id: id, name: "", raw_length: 0), status: "decoded",
                image_path: "\(type)-\(id)-\(frame).png", width: 32, height: 32,
                mode: "RGBA", frame_index: frame, frame_count: 2, palette: nil)
        }
        for images in [[entry("Imag"), entry("cicn"), entry("Ima4"), entry("Imag", 1)],
                       [entry("cicn"), entry("Ima4"), entry("Imag"), entry("Imag", 1)]] {
            let manifest = GraphicsManifest(source_file: "synthetic", images: images)
            #expect(manifest.image(resource: id, type: "cicn")?.image_path == "cicn-\(id)-0.png")
            #expect(manifest.image(resource: id, type: "Ima4")?.image_path == "Ima4-\(id)-0.png")
            #expect(manifest.image(resource: id, type: "Imag", frame: 1)?.image_path == "Imag-\(id)-1.png")
            #expect(manifest.image(resource: id, type: "cicn", frame: 1) == nil)
            #expect(manifest.image(resource: id, type: "ICON") == nil)
            #expect(manifest.image(resource: id)?.image_path == images[0].image_path)
            #expect(manifest.image(resource: id + 1, type: "cicn") == nil)
        }
    }

    @Test func aboutIdentifiesTheIndependentApp() {
        #expect(OriginalAboutRules.program == "Oregon Bound")
        #expect(OriginalAboutRules.copyright == "Copyright 2026 Sierra Burkhart")
        #expect(OriginalAboutRules.State().heading == "Original game team:")
        #expect(OriginalAboutRules.attribution.contains("Not affiliated or endorsed."))
    }
}
