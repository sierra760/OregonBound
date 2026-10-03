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
            + [resource("PICT", 129, CDGuidePictureTests.picture([], frame: [0, 0, 792, 612]))]
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
        #expect(Set(guide.pictures.keys) == Set([10, 30, 20, 90, 129]))
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
        #expect(try CDUserGuide(fork: MacResourceFork(resources: valid + [orphan])).pictures.count == 5)
    }

    @Test func preparedGuideIncludesPaperAndOnlyReferencedResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = Self.userGuideResources() + [
            MacResource(type: "CODE", id: 0, name: nil, attributes: 0, data: Data([1, 2, 3])),
            MacResource(type: "PICT", id: 1500, name: nil, attributes: 0, data: Data([0]))]
        let fork = MacResourceFork(resources: resources)
        let guide = try CDUserGuide.extract(from: fork, into: ExtractionOutput(root: root))
        #expect(guide.pictures.count == 5 && guide.pictures[129] != nil)
        let source = MacForkSource(displayName: "manual", origin: "synthetic", fileType: nil, creator: nil,
                                   dataFork: Data(), resourceFork: Data([1]))
        let catalog = try GameResourceCatalog(selection: .init(edition: .macintoshCD12,
            sources: [.cdUserGuide: .init(source: source, fork: fork)], unrecognized: []))
        let loaded = try CDUserGuide.load(root: root, catalog: catalog)
        #expect(loaded.pageIDs == guide.pageIDs && loaded.pictures == guide.pictures)
        #expect(loaded.links == guide.links && loaded.sections == guide.sections)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("user-guide/resources/CODE_0.bin").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("user-guide/resources/PICT_1500.bin").path))
        #expect(throws: (any Error).self) {
            try CDUserGuide.extract(from: MacResourceFork(resources: Self.userGuideResources().filter { !($0.type == "PICT" && $0.id == 129) }), into: ExtractionOutput(root: root))
        }
    }

    @Test(arguments: ["changed", "truncated", "missing", "symlink", "missing-index-entry", "duplicate-index-entry",
                      "unreferenced", "invalid-type", "invalid-id", "excessive-index", "catalog-hash", "catalog-role", "catalog-length"])
    func preparedGuideRejectsTamperingAndEscapingResources(kind: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let extra = MacResource(type: "PICT", id: 99, name: nil, attributes: 0,
                                data: CDGuidePictureTests.picture([], frame: [0, 0, 2, 2]))
        let fork = MacResourceFork(resources: Self.userGuideResources() + [extra])
        let source = MacForkSource(displayName: "manual", origin: "synthetic", fileType: nil, creator: nil,
                                   dataFork: Data(), resourceFork: Data([1]))
        var catalog = try GameResourceCatalog(selection: .init(edition: .macintoshCD12,
            sources: [.cdUserGuide: .init(source: source, fork: fork)], unrecognized: []))
        _ = try CDUserGuide.extract(from: fork, into: ExtractionOutput(root: root))
        let pictureURL = root.appendingPathComponent("user-guide/resources/PICT_10.bin")
        let indexURL = root.appendingPathComponent("user-guide/document.json")
        var index = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [[String: Any]])
        switch kind {
        case "changed":
            var bytes = try Data(contentsOf: pictureURL); bytes[3] ^= 1; try bytes.write(to: pictureURL)
        case "truncated": try Data([0]).write(to: pictureURL)
        case "missing": try FileManager.default.removeItem(at: pictureURL)
        case "symlink":
            try FileManager.default.copyItem(at: pictureURL, to: outside)
            try FileManager.default.removeItem(at: pictureURL)
            try FileManager.default.createSymbolicLink(at: pictureURL, withDestinationURL: outside)
        case "missing-index-entry": index.removeFirst()
        case "duplicate-index-entry": index.append(index[0])
        case "unreferenced":
            index.append(["type": "PICT", "id": 99])
            try extra.data.write(to: root.appendingPathComponent("user-guide/resources/PICT_99.bin"))
        case "invalid-type": index[0]["type"] = "../PICT"
        case "invalid-id": index[0]["id"] = -1
        case "excessive-index": try Data(repeating: 32, count: 4 * 1024 * 1024 + 1).write(to: indexURL)
        default:
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
            var entries = try #require(object["entries"] as? [[String: Any]])
            let i = try #require(entries.firstIndex { $0["type"] as? String == "PICT" && $0["id"] as? Int == 10 })
            if kind == "catalog-hash" { entries[i]["sha256"] = String(repeating: "0", count: 64) }
            if kind == "catalog-role" { entries[i]["role"] = "cdApplication" }
            if kind == "catalog-length" { entries[i]["length"] = Int.max }
            object["entries"] = entries
            catalog = try JSONDecoder().decode(GameResourceCatalog.self, from: JSONSerialization.data(withJSONObject: object))
        }
        if kind != "excessive-index" { try JSONSerialization.data(withJSONObject: index).write(to: indexURL) }
        #expect(throws: (any Error).self) { try CDUserGuide.load(root: root, catalog: catalog) }
    }

    @Test func guidePreparationRejectsUnsupportedPicturesAndWrongPaperBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (id, bytes) in [(10, CDGuidePictureTests.picture([(0x1234, Data())])),
                            (129, CDGuidePictureTests.picture([], frame: [0, 0, 792, 611]))] {
            let resources = Self.userGuideResources().map { resource in
                resource.type == "PICT" && resource.id == id
                    ? MacResource(type: "PICT", id: id, name: nil, attributes: 0, data: bytes) : resource
            }
            #expect(throws: (any Error).self) {
                try CDUserGuide.extract(from: MacResourceFork(resources: resources), into: ExtractionOutput(root: root))
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("user-guide/document.json").path))
    }

}


struct CDUserGuideNavigationTests {
    @Test func comparisonViewsNavigateIndependentlyButShareTheDocumentsReturnHistory() throws {
        var document = CDUserGuideRules.Views(state: try state())
        document.update(0) { $0.setOffset(x: 5, y: 10) }
        document.openComparison()
        #expect(document.states.count == 2 && document.states[1].offset == .init(x: 5, y: 10))
        document.update(1) { $0.activateLink(at: 0); $0.setZoom(tenths: 20) }
        #expect(document.states[0].pageID == 10 && document.states[0].zoomTenths == 10)
        #expect(document.states[1].pageID == 30 && document.states[1].zoomTenths == 20)
        #expect(document.states[0].history == document.states[1].history)
        document.update(0) { $0.returnToHistory() }
        #expect(document.states[0].offset == .init(x: 5, y: 10) && document.states[1].history.isEmpty)
        document.openComparison(); #expect(document.states.count == 2)
        document.update(2) { $0.page(forward: true) }
        document.closeComparison(); #expect(document.states.count == 1 && document.states[0].pageID == 10)
    }

    private func state() throws -> CDUserGuideRules.State {
        try .init(guide: CDUserGuide(fork: MacResourceFork(resources: GameDataPreparationTests.userGuideResources())),
                  viewportWidth: 300, viewportHeight: 200)
    }
    @Test func screenStepsWithinPaperBeforeChangingPagesAndDoesNotRecordHistory() throws {
        var reader = try state()
        reader.screen(forward: true)
        #expect(reader.pageID == 10 && reader.offset == .init(x: 0, y: 184))
        reader.setOffset(x: 50, y: 588)
        reader.screen(forward: true)
        #expect(reader.pageID == 30 && reader.offset == .zero)
        reader.screen(forward: false)
        #expect(reader.pageID == 10 && reader.offset == .init(x: 0, y: 592))
        reader.screen(forward: false)
        #expect(reader.offset.y == 408 && reader.history.isEmpty)
        reader.page(forward: false)
        #expect(reader.pageID == 10 && reader.offset.y == 408)
        reader.page(forward: true)
        reader.page(forward: true)
        reader.setOffset(x: 0, y: 592); reader.screen(forward: true)
        #expect(reader.pageID == 20 && reader.offset.y == 592)
    }
    @Test func topicHistoryStoresLocationsAndSelectingAnOlderEntryRemovesOnlyThatEntry() throws {
        var reader = try state()
        reader.setOffset(x: 25, y: 50)
        reader.activateLink(at: 0)
        #expect(reader.pageID == 30 && reader.offset == .init(x: 0, y: 100))
        #expect(reader.history.count == 1 && reader.history[0].pageID == 10)
        reader.chooseSection(at: 0)
        #expect(reader.pageID == 10 && reader.offset == .zero && reader.history.count == 2)
        reader.returnToHistory(at: 0)
        #expect(reader.pageID == 10 && reader.offset == .init(x: 25, y: 50))
        #expect(reader.history.count == 1 && reader.history[0].pageID == 30)
        reader.returnToHistory()
        #expect(reader.pageID == 30 && reader.offset.y == 100 && reader.history.isEmpty)
        reader.returnToHistory(); reader.activateLink(at: -1); reader.chooseSection(at: 99)
        #expect(reader.pageID == 30 && reader.history.isEmpty)
    }
    @Test func captionsAndPaperHitTestingDoNotNavigateOrAddHistory() throws {
        var reader = try state()
        reader.setZoom(tenths: 20)
        reader.setOffset(x: 100, y: 10)
        #expect(reader.linkIndex(at: .init(x: 80, y: 50)) == 1)
        reader.activateLink(at: 1)
        #expect(reader.caption?.destination == 90 && reader.pageID == 10 && reader.history.isEmpty)
        #expect(reader.caption?.destinationRect == .init(top: 10, left: 0, bottom: 30, right: 200))
        reader.dismissCaption()
        #expect(reader.caption == nil)
        #expect(reader.linkIndex(at: .init(x: -1, y: 0)) == nil)
        reader.activateLink(at: 0)
        #expect(reader.pageID == 30 && reader.offset == .init(x: 0, y: 200))
    }
    @Test func zoomMenuResetsWhileMagnifierCentersAndClampsClickedPoint() throws {
        var reader = try state()
        reader.setOffset(x: 100, y: 100)
        reader.magnify(at: .init(x: 150, y: 100), increase: true)
        #expect(reader.zoomTenths == 20 && reader.offset == .init(x: 350, y: 300))
        reader.setZoom(tenths: 30)
        #expect(reader.zoomTenths == 30 && reader.offset == .zero)
        reader.setZoom(tenths: 0)
        #expect(reader.zoomTenths == 30)
        reader.setZoom(tenths: 5)
        reader.magnify(at: .zero, increase: false)
        #expect(reader.zoomTenths == 5 && reader.offset == .zero)
        reader.setZoom(tenths: 50); reader.magnify(at: .zero, increase: true)
        #expect(reader.zoomTenths == 50)
        reader.setOffset(x: Int.max, y: Int.max)
        #expect(reader.offset == .init(x: 2760, y: 3760))
        reader.resize(width: Int.max, height: Int.max)
        #expect(reader.offset == .zero)
    }
    @Test func returnHistoryUsesTheOriginalCurrentMagnificationAndSectionNumbering() throws {
        var reader = try state()
        #expect(reader.pageNumber == "1")
        reader.setOffset(x: 20, y: 40); reader.activateLink(at: 0)
        reader.setZoom(tenths: 20); reader.returnToHistory()
        #expect(reader.offset == .init(x: 40, y: 80))
        reader.chooseSection(at: 1)
        #expect(reader.pageNumber == "2" && reader.sectionIndex == 1)
        reader.page(forward: true)
        #expect(reader.pageNumber == "3")
        let before = reader.offset
        reader.chooseSection(at: 1)
        #expect(reader.pageID == 30 && reader.offset == .zero)
        reader.setOffset(x: 5, y: 8); reader.chooseSection(at: 1)
        #expect(reader.offset == .init(x: 5, y: 8))
        #expect(before == .zero)
    }
}
