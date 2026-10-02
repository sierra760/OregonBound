import Foundation
import Testing
@testable import OregonBound

struct GameDataPreparationTests {
    @Test func malformedApplicationCannotReplaceAnInstalledPreparation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("prepared")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: destination.appendingPathComponent("sentinel"))
        var sources: [GameDataSourceRole: GameDataSourceCatalog.Candidate] = [:]
        for role in GameEdition.macintoshCD12.requiredRoles {
            let resources = GameSourceRequirements.resources(for: role).flatMap { type, ids in
                ids.map { MacResource(type: type, id: $0, name: nil, attributes: 0, data: Data([1])) }
            }
            let source = MacForkSource(displayName: role.rawValue, origin: role.rawValue, fileType: nil, creator: nil,
                                       dataFork: Data(), resourceFork: Data(role.rawValue.utf8))
            sources[role] = .init(source: source, fork: MacResourceFork(resources: resources))
        }
        let selection = GameDataSourceCatalog.Selection(edition: .macintoshCD12, sources: sources, unrecognized: [])
        #expect(throws: (any Error).self) {
            try GameDataPreparation.run(selection: selection, destination: destination, progress: { _ in })
        }
        let previous = try String(contentsOf: destination.appendingPathComponent("sentinel"), encoding: .utf8)
        #expect(previous == "previous")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["prepared"])
    }

    @Test func strictTextValidationRejectsTruncatedLists() {
        for (type, bytes): (String, [UInt8]) in [("STR#", [0, 1, 3, 97]), ("DITL", [0, 0]), ("HVof", [1])] {
            let fork = MacResourceFork(resources: [MacResource(type: type, id: 1, name: nil, attributes: 0, data: Data(bytes))])
            #expect(throws: (any Error).self) { try TextResourceExtractors.validate(fork) }
        }
    }

    static func styleScrap(_ starts: [UInt32], padding: UInt8 = 0) -> Data {
        var data = Data(); data.appendU16(UInt16(starts.count))
        for (index, start) in starts.enumerated() {
            data.appendU32(start)
            data.appendU16(15); data.appendU16(10); data.appendU16(21)
            data.append(UInt8(index % 2)); data.append(padding)
            data.appendU16(12)
            data.appendU16(0); data.appendU16(0); data.appendU16(0)
        }
        return data
    }

    @Test func styledCreditsPreserveMacRomanByteOffsetsAndCarriageReturns() throws {
        let text = Data([0x8e, 0x0d, 0x0d, 0x41, 0x20, 0x42, 0x0d])
        let parsed = try CDAboutCredits(text: text, styles: Self.styleScrap([0, 3], padding: 13))
        #expect(parsed.bytes == Array(text))
        #expect(parsed.text == "é\r\rA B\r")
        #expect(parsed.runs.map(\.start) == [0, 3])
        #expect(parsed.runs.map(\.face) == [0, 1])
        #expect(parsed.runs.allSatisfy { $0.height == 15 && $0.ascent == 10 && $0.font == 21 && $0.size == 12 })
        #expect(parsed.runs.allSatisfy { $0.red == 0 && $0.green == 0 && $0.blue == 0 })
        #expect(parsed == (try CDAboutCredits(text: text, styles: Self.styleScrap([0, 3]))))
    }

    @Test func styledCreditsRejectMalformedRunTablesAndExcessiveText() throws {
        let text = Data("Sample".utf8)
        for starts: [UInt32] in [[], [1], [0, 0], [0, 4, 3], [0, 6], [0, UInt32.max]] {
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: Self.styleScrap(starts)) }
        }
        let valid = Self.styleScrap([0])
        for length in 0..<valid.count {
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: valid.prefix(length)) }
        }
        #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: valid + Data([0])) }
        for (offset, value): (Int, UInt16) in [(6, 0), (6, 0xffff), (8, 16), (8, 0xffff), (10, 0xffff), (14, 0), (14, 0xffff)] {
            var malformed = valid
            malformed[offset] = UInt8(value >> 8); malformed[offset + 1] = UInt8(value & 255)
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: malformed) }
        }
        var face = valid; face[12] = 0x80
        #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: face) }
        #expect(throws: (any Error).self) { try CDAboutCredits(text: Data(repeating: 65, count: 32768), styles: valid) }
        #expect(try CDAboutCredits(text: Data(repeating: 65, count: 32767), styles: valid).bytes.count == 32767)
        #expect(try CDAboutCredits(text: Data(), styles: Self.styleScrap([])).runs.isEmpty)
        #expect(throws: (any Error).self) { try CDAboutCredits(text: Data(), styles: valid) }
    }

    @Test func extractsValidatedCreditsFromPlayerResourcesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = Data("Team\rSample\r".utf8), styles = Self.styleScrap([0, 5])
        let fork = MacResourceFork(resources: [
            .init(type: "TEXT", id: 200, name: nil, attributes: 0, data: text),
            .init(type: "styl", id: 200, name: nil, attributes: 0, data: styles)])
        try CDAboutCredits.extract(from: fork, into: ExtractionOutput(root: root))
        #expect(try Data(contentsOf: root.appendingPathComponent("runtime/about_text_200.bin")) == text)
        #expect(try Data(contentsOf: root.appendingPathComponent("runtime/about_styl_200.bin")) == styles)
        #expect(throws: (any Error).self) {
            try CDAboutCredits.extract(from: MacResourceFork(resources: []), into: ExtractionOutput(root: root))
        }
    }

    @Test func styledCreditLayoutUsesFontMetricsAndMixedStyleByteWidths() throws {
        let credits = try CDAboutCredits(text: Data("AB CD\r\rE".utf8), styles: Self.styleScrap([0, 2]))
        var advances = Array(repeating: 3, count: 256); advances[13] = 0; advances[32] = 2
        let layout = try credits.layout(advances: advances, lineHeight: 14, width: 10)
        #expect(layout.lineStarts == [0, 3, 6, 7, 8])
        #expect(layout.textHeight == 56 && layout.bufferHeight == 171)
        #expect(layout.glyphs.map(\.byteOffset) == [0, 1, 2, 3, 4, 7])
        #expect(layout.glyphs.map(\.x) == [0, 3, 6, 0, 4, 0])
        #expect(layout.glyphs.map(\.y) == [0, 0, 0, 14, 14, 42])
        #expect(layout.glyphs.map(\.bold) == [false, false, true, true, true, true])
        let trailing = try CDAboutCredits(text: Data("A\r".utf8), styles: Self.styleScrap([0]))
        #expect(try trailing.layout(advances: advances, lineHeight: 14).textHeight == 14)
        let empty = try CDAboutCredits(text: Data(), styles: Self.styleScrap([]))
        #expect(try empty.layout(advances: advances, lineHeight: 14).bufferHeight == 115)
    }

    @Test func creditLayoutRejectsUnsupportedStylesAndUnsafeMetrics() throws {
        let text = Data("Sample".utf8), style = Self.styleScrap([0])
        let credits = try CDAboutCredits(text: text, styles: style)
        let advances = Array(repeating: 3, count: 256)
        for height in [0, -1, 32767] {
            #expect(throws: (any Error).self) { try credits.layout(advances: advances, lineHeight: height) }
        }
        #expect(throws: (any Error).self) { try credits.layout(advances: [3], lineHeight: 14) }
        var negative = advances; negative[65] = -1
        #expect(throws: (any Error).self) { try credits.layout(advances: negative, lineHeight: 14) }
        for (offset, value): (Int, UInt8) in [(11, 3), (12, 2), (15, 14), (16, 1)] {
            var changed = style; changed[offset] = value
            let unsupported = try CDAboutCredits(text: text, styles: changed)
            #expect(throws: (any Error).self) { try unsupported.layout(advances: advances, lineHeight: 14) }
        }
    }

    static func userGuideResources() -> [MacResource] {
        func words(_ values: [UInt16]) -> Data {
            var data = Data(); for value in values { data.appendU16(value) }; return data
        }
        func resource(_ type: String, _ id: Int, _ data: Data) -> MacResource {
            .init(type: type, id: id, name: nil, attributes: 0, data: data)
        }
        // Page-map order is independent of resource ID order. Counts here are zero-based.
        let pageMap = words([2, 0, 10, 0, 30, 0, 20])
        let sections = words([1, 1, 1, 1, 2, 3, 0xff80])
        let titles = Data([0, 2, 1, 0x8e, 5]) + Data("Trail".utf8)
        let picture = words([16, 0xffff, 0xffff, 40, 60, 0x11, 0x2ff, 0xff])
        // Link bounds live on the paper, intentionally outside the picture's local frame.
        let goTo = words([10, 400, 25, 500, 2, 0x017f, 0, 30, 100, 0, 150, 600])
        let caption = words([30, 90, 50, 120, 3, 0, 0, 90, 10, 0, 30, 200])
        return [resource("PMAP", 128, pageMap), resource("SCNM", 128, sections),
                resource("STR#", 128, titles), resource("RECT", 10, words([2]) + goTo + caption),
                resource("RECT", 30, words([1]) + caption), resource("RECT", 20, words([0]))]
            + [10, 30, 20, 90].map { resource("PICT", $0, picture) }
    }

    @Test func userGuidePreservesPageOrderSectionsAndPaperSpaceLinks() throws {
        let resources = Self.userGuideResources()
        let guide = try CDUserGuide(fork: MacResourceFork(resources: resources))
        #expect(guide.pageIDs == [10, 30, 20])
        #expect(guide.sections.map(\.title) == ["é", "Trail"])
        #expect(guide.sections.map(\.firstPage) == [1, 2])
        #expect(guide.sections.map(\.lastPage) == [1, 3])
        #expect(guide.sections.map(\.numbering) == [1, -128])
        let link = try #require(guide.links[10]?.first)
        #expect(link.bounds == .init(top: 10, left: 400, bottom: 25, right: 500))
        #expect(link.kind == .goTo && link.openCheck && link.destination == 30)
        #expect(link.destinationRect == .init(top: 100, left: 0, bottom: 150, right: 600))
        #expect(guide.links[10]?.last?.kind == .caption)
        #expect(guide.links[30]?.first?.destination == 90)
        #expect(guide.links[20] == [])
        #expect(Set(guide.pictures.keys) == Set([10, 30, 20, 90]))
        for resource in resources where resource.type == "PICT" {
            #expect(guide.pictures[resource.id] == resource.data)
        }
    }

    @Test func userGuideRejectsIncompleteTablesAndDanglingDestinations() throws {
        let valid = Self.userGuideResources()
        func replacing(_ original: MacResource, with bytes: Data) -> MacResourceFork {
            MacResourceFork(resources: valid.map {
                $0.type == original.type && $0.id == original.id
                    ? .init(type: $0.type, id: $0.id, name: nil, attributes: 0, data: bytes) : $0
            })
        }
        for original in valid where original.type != "PICT" {
            for length in 0..<original.data.count {
                #expect(throws: (any Error).self) {
                    try CDUserGuide(fork: replacing(original, with: original.data.prefix(length)))
                }
            }
            #expect(throws: (any Error).self) {
                try CDUserGuide(fork: replacing(original, with: original.data + Data([0])))
            }
        }
        for original in valid {
            #expect(throws: (any Error).self) {
                try CDUserGuide(fork: MacResourceFork(resources: valid.filter { $0 != original }))
            }
        }
        let changes: [(String, Int, Int, UInt16)] = [
            ("PMAP", 128, 0, 256), ("PMAP", 128, 8, 10), ("PMAP", 128, 4, 0xffff),
            ("SCNM", 128, 2, 0), ("SCNM", 128, 8, 1), ("SCNM", 128, 10, 4),
            ("SCNM", 128, 10, 2), ("SCNM", 128, 6, 99), ("STR#", 128, 0, 1),
            ("RECT", 10, 0, 4097), ("RECT", 10, 2, 25), ("RECT", 10, 10, 4),
            ("RECT", 10, 12, 0x0200), ("RECT", 10, 16, 90), ("RECT", 10, 40, 91),
            ("RECT", 10, 18, 150), ("PICT", 90, 10, 0x1111), ("PICT", 90, 8, 0xffff)
        ]
        for (type, id, offset, value) in changes {
            let original = try #require(valid.first { $0.type == type && $0.id == id })
            var bytes = original.data
            bytes[offset] = UInt8(value >> 8); bytes[offset + 1] = UInt8(value & 255)
            #expect(throws: (any Error).self) { try CDUserGuide(fork: replacing(original, with: bytes)) }
        }
        #expect(throws: (any Error).self) {
            try CDUserGuide(fork: MacResourceFork(resources: valid + [valid[0]]))
        }
        let picture = try #require(valid.first { $0.type == "PICT" })
        #expect(throws: (any Error).self) {
            try CDUserGuide(fork: replacing(picture, with: Data(repeating: 0, count: 4 * 1024 * 1024 + 1)))
        }
        // An orphan empty RECT is present in the supplied reader. It is not document content.
        let orphan = MacResource(type: "RECT", id: 91, name: nil, attributes: 0, data: Data([0, 0]))
        #expect(try CDUserGuide(fork: MacResourceFork(resources: valid + [orphan])).pictures.count == 4)
    }

}
