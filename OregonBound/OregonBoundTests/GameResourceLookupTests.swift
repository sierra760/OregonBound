import Foundation
import Testing
@testable import OregonBound

struct GameResourceLookupTests {
    private func entry(_ role: GameDataSourceRole, _ type: String = "Imag", _ id: Int = 42,
                       disposition: GameResourceCatalog.Disposition = .resource) -> GameResourceCatalog.Entry {
        .init(role: role, type: type, id: id, name: nil, attributes: 0, length: 2,
              sha256: "synthetic", disposition: disposition)
    }

    @Test func companionsOverrideApplicationRegardlessOfInputOrder() throws {
        let entries = [entry(.cdApplication), entry(.graphics2), entry(.system)]
        for input in [entries, Array(entries.reversed())] {
            let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: input)
            #expect(lookup.resource(type: "Imag", id: 42)?.role == .graphics2)
            #expect(lookup.index.entries.count == 1)
        }
        let fallback = try GameResourceLookup(edition: .macintoshCD12, entries: [entry(.system), entry(.cdApplication)])
        #expect(fallback.resource(type: "Imag", id: 42)?.role == .cdApplication)
    }

    @Test func ambiguousDuplicateAndForeignSourcesAreRejected() {
        for entries in [[entry(.graphics1), entry(.graphics2)],
                        [entry(.graphics1), entry(.graphics1)],
                        [entry(.classicApplication)]] {
            #expect(throws: (any Error).self) { try GameResourceLookup(edition: .macintoshCD12, entries: entries) }
        }
    }

    @Test func emptyCompanionDoesNotFallBackToApplication() throws {
        let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: [
            entry(.cdApplication), entry(.graphics2, disposition: .emptyPlaceholder)])
        #expect(lookup.resource(type: "Imag", id: 42)?.disposition == .emptyPlaceholder)
    }

    @Test func cdUsesExplicitIdsAndSeparateImageAndDisplayDepths() throws {
        let lookup = try GameResourceLookup(edition: .macintoshCD12, entries: [
            entry(.graphics2, "Imag", 7), entry(.graphics1, "Imag", 93), entry(.graphics3, "Ima4", 93)])
        #expect(try lookup.cdImage(monochromeID: 7, colorID: 93, imageDepth: .monochrome, displayDepth: .monochrome)?.id == 7)
        #expect(try lookup.cdImage(monochromeID: 7, colorID: 93, imageDepth: .color256, displayDepth: .color256)?.role == .graphics1)
        #expect(try lookup.cdImage(monochromeID: 7, colorID: 93, imageDepth: .color16, displayDepth: .color16)?.role == .graphics3)
        // Object ID selection and global resource-type selection are distinct.
        #expect(try lookup.cdImage(monochromeID: 7, colorID: 93, imageDepth: .monochrome, displayDepth: .color16) == nil)
        #expect(try lookup.cdImage(monochromeID: 7, colorID: 94, imageDepth: .color256, displayDepth: .color256) == nil)
    }

    @Test func classicLookupKeepsItsEditionAndRejectsCDSelector() throws {
        let lookup = try GameResourceLookup(edition: .macintosh11, entries: [entry(.classicApplication), entry(.classicGraphics)])
        #expect(lookup.index.edition == .macintosh11)
        #expect(lookup.resource(type: "Imag", id: 42)?.role == .classicGraphics)
        #expect(throws: (any Error).self) {
            try lookup.cdImage(monochromeID: 7, colorID: 93, imageDepth: .color256, displayDepth: .color256)
        }
    }
}
