import Foundation
import Testing
@testable import OregonBound

struct GameDataSourceTests {
    private func resource(_ type: String, _ id: Int = 0, _ bytes: [UInt8] = [1]) -> MacResource {
        MacResource(type: type, id: id, name: nil, attributes: 0, data: Data(bytes))
    }
    private func source(_ resources: [MacResource], name: String = "renamed", tag: String) -> GameDataSourceCatalog.Candidate {
        let source = MacForkSource(displayName: name, origin: tag, fileType: nil, creator: nil,
                                   dataFork: Data(), resourceFork: Data(tag.utf8))
        return .init(source: source, fork: MacResourceFork(resources: resources))
    }
    private func application(cd: Bool) -> GameDataSourceCatalog.Candidate {
        var records = [resource("vers", 1, [1, cd ? 0x20 : 0x10]), resource(cd ? "OTCD" : "ORGN"),
                       resource("DITL"), resource("STR#", 3150), resource("WST#", 3151),
                       resource("NFNT"), resource("HVof")]
        if !cd { records.append(resource("snd ", 9001)) }
        return source(records, tag: cd ? "cd-app" : "classic-app")
    }
    private func classicGraphics() -> GameDataSourceCatalog.Candidate {
        source([resource("vers", 1, [1, 0x10]), resource("Imag", 10128), resource("cicn"), resource("clut")], tag: "classic-graphics")
    }
    private func cdCompanions() -> [GameDataSourceCatalog.Candidate] {
        let graphics = [
            source([resource("OTSG", 128, []), resource("Imag", 10128), resource("cicn")], tag: "g1"),
            source([resource("OTSG", 133, []), resource("Imag", 128), resource("TERR"), resource("clut")], tag: "g2"),
            source([resource("Ima4", 10128), resource("Ima4", 20300)], tag: "g3"),
            source((20200...20262).map { resource("Ima4", $0) }, tag: "g4")
        ]
        var soundGroups: [[Int]] = [Array(6001...6024), Array(6025...6049), Array(6050...6073)]
        soundGroups.append((310...318).flatMap { n -> [Int] in [n * 10 + 1, n * 10 + 2, n * 10 + 3] })
        soundGroups.append((319...327).flatMap { n -> [Int] in [n * 10 + 1, n * 10 + 2, n * 10 + 3] })
        soundGroups.append(Array(1000...1005) + [2000])
        soundGroups.append(Array(1006...1017))
        var effects = Array(4000...4015)
        effects += [4020]
        effects += Array(9001...9008)
        effects += Array(10000...10003)
        soundGroups.append(effects)
        return graphics + soundGroups.enumerated().map { index, ids in
            source(ids.map { resource("snd ", $0) }, tag: "sound-\(index)")
        }
    }

    @Test func classicSelectionUsesContentsAndOptionalSystem() throws {
        let system = source([resource("CDEF", 1), resource("FOND", 0), resource("FOND", 3), resource("ICON", 0)], tag: "system")
        let selection = try GameDataSourceCatalog.select([classicGraphics(), system, application(cd: false)])
        #expect(selection.edition == .macintosh11)
        #expect(selection.sources.count == 3)
        #expect(selection.sources[.classicGraphics]?.source.origin == "classic-graphics")
    }

    @Test func cdSelectionIncludesEveryCompanionWithoutEmbeddedSound() throws {
        let selection = try GameDataSourceCatalog.select(cdCompanions().reversed() + [application(cd: true)])
        #expect(selection.edition == .macintoshCD12)
        #expect(selection.sources.count == 13)
        #expect(selection.sources[.graphics4]?.fork.resources.count == 63)
        #expect(selection.sources[.guide3]?.fork.resources.count == 24)
    }

    @Test func identicalCopiesDeduplicateButConflictsDoNotChooseByName() throws {
        let graphics = classicGraphics()
        let selection = try GameDataSourceCatalog.select([application(cd: false), graphics, graphics])
        #expect(selection.sources.count == 2)
        let conflict = source(graphics.fork.resources, name: "Oregon Color", tag: "different-graphics")
        #expect(throws: (any Error).self) {
            try GameDataSourceCatalog.select([application(cd: false), graphics, conflict])
        }
    }

    @Test func missingCompanionsReportRoles() {
        do {
            _ = try GameDataSourceCatalog.select([application(cd: true)])
            Issue.record("Incomplete CD source set was accepted")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("Graphics 1"))
            #expect(message.contains("Guide Book 3"))
            #expect(message.contains("Oregon Sound 5"))
        }
    }

    @Test func mixedEditionsAndDuplicateResourceIdentitiesAreRejected() {
        #expect(throws: (any Error).self) {
            try GameDataSourceCatalog.select([application(cd: false), classicGraphics(), application(cd: true)] + cdCompanions())
        }
        #expect(throws: (any Error).self) {
            try GameDataSourceCatalog.select([application(cd: true), classicGraphics()] + cdCompanions())
        }
        let graphics = classicGraphics()
        let corrupt = source(graphics.fork.resources + [resource("Imag", 10128)], tag: "duplicate-resource")
        #expect(throws: (any Error).self) {
            try GameDataSourceCatalog.select([application(cd: false), corrupt])
        }
    }

    @Test func unsupportedVersionIsNotTreatedAsClassic() {
        var records = application(cd: true).fork.resources.filter { $0.type != "vers" }
        records.append(resource("vers", 1, [2, 0]))
        #expect(throws: (any Error).self) {
            try GameDataSourceCatalog.select([source(records, tag: "unknown-version")] + cdCompanions())
        }
    }
    @Test func catalogPreservesSourceTypeIDAndPayloadHashes() throws {
        let selected = try GameDataSourceCatalog.select(cdCompanions() + [application(cd: true)])
        let catalog = try GameResourceCatalog(selection: selected)
        let alternatives = catalog.entries.filter { $0.id == 10128 }
        #expect(alternatives.count == 2)
        #expect(Set(alternatives.map(\.type)) == Set(["Imag", "Ima4"]))
        #expect(Set(alternatives.map(\.role)) == Set([.graphics1, .graphics3]))
        #expect(catalog.entries.count == selected.sources.values.reduce(0) { $0 + $1.fork.resources.count })
        #expect(catalog.sources.count == 13)
        #expect(catalog.entries.allSatisfy { $0.sha256.count == 64 && $0.length > 0 || $0.type == "OTSG" })
        #expect(catalog.edition == .macintoshCD12)
    }

    @Test func onlyKnownEmptyGraphicsArePlaceholders() throws {
        var companions = cdCompanions()
        let original = companions[0]
        companions[0] = source(original.fork.resources + [resource("Imag", 15522, [0, 0])], tag: "g1-empty")
        let selected = try GameDataSourceCatalog.select(companions + [application(cd: true)])
        let catalog = try GameResourceCatalog(selection: selected)
        #expect(catalog.entries.first { $0.role == .graphics1 && $0.id == 15522 }?.disposition == .emptyPlaceholder)
        companions[0] = source(original.fork.resources + [resource("Imag", 12345, [0, 0])], tag: "unexpected-empty")
        #expect(throws: (any Error).self) {
            try GameResourceCatalog(selection: GameDataSourceCatalog.select(companions + [application(cd: true)]))
        }
    }

}
