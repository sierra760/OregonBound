import Foundation
import Testing
@testable import OregonBound

struct PreparedTerrainTests {
    private func entry(_ role: GameDataSourceRole = .graphics2, id: Int = 19200, length: Int = 14) -> GameResourceCatalog.Entry {
        .init(role: role,type: "TERR",id: id,name: nil,attributes: 0,length: length,sha256: "synthetic",disposition: .resource)
    }
    private func terrain(id: Int = 19200, right: Int = 25) -> TerrainExtractor.Terrain {
        .init(resourceID: id,leftEntryAllowed: true,rightEntryAllowed: false,
              obstacles: [.init(top: 100,left: 15,bottom: 110,right: right)])
    }
    private func temporary() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    private func write(_ terrain: TerrainExtractor.Terrain, root: URL, role: GameDataSourceRole = .graphics2) throws {
        try ExtractionOutput(root: root).writeJSON(terrain,to: "sources/\(role.rawValue)/terrain/terr_19200.json")
    }

    @Test func effectiveTerrainIsCapturedWithNoFallbackOrLaterFileDependency() throws {
        let root = temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let lookup = try GameResourceLookup(edition: .macintoshCD12,entries: [entry(.cdApplication),entry()])
        try write(terrain(),root: root)
        try write(terrain(right: 99),root: root,role: .cdApplication)
        let library = try PreparedTerrainLibrary(root: root,lookup: lookup,terrainSources: [.cdApplication,.graphics2])
        #expect(library.terrain(19200)?.obstacles.first?.right == 25)
        #expect(library.terrain(19201) == nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("sources/graphics2/terrain/terr_19200.json"))
        #expect(library.terrain(19200)?.obstacles.first?.right == 25)
        #expect(throws: (any Error).self) {
            try PreparedTerrainLibrary(root: root,lookup: lookup,terrainSources: [.cdApplication,.graphics2])
        }
        let excluded = try PreparedTerrainLibrary(root: root,lookup: lookup,terrainSources: [.cdApplication])
        #expect(excluded.terrain(19200) == nil)
    }

    @Test(arguments: ["identity", "empty_rect", "coordinate", "length", "symlink", "missing", "duplicate_source", "foreign_source"])
    func rejectsMalformedTerrainBeforeActivation(kind: String) throws {
        let root = temporary(), outside = temporary()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let lookup = try GameResourceLookup(edition: .macintoshCD12,entries: [entry(length: kind == "length" ? 22 : 14)])
        let value = terrain(id: kind == "identity" ? 19201 : 19200,
                            right: kind == "empty_rect" ? 15 : kind == "coordinate" ? 32768 : 25)
        try write(value,root: root)
        let file = root.appendingPathComponent("sources/graphics2/terrain/terr_19200.json")
        if kind == "missing" { try FileManager.default.removeItem(at: file) }
        if kind == "symlink" {
            try FileManager.default.moveItem(at: file,to: outside)
            try FileManager.default.createSymbolicLink(at: file,withDestinationURL: outside)
        }
        let sources: [GameDataSourceRole] = kind == "duplicate_source" ? [.graphics2,.graphics2]
            : kind == "foreign_source" ? [.classicGraphics] : [.graphics2]
        #expect(throws: (any Error).self) { try PreparedTerrainLibrary(root: root,lookup: lookup,terrainSources: sources) }
    }

    @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func preparedSessionRequiresTerrainSourcesToMatchCatalog(edition: GameEdition) throws {
        let root = try PreparedSessionFixture.make(edition: edition)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try PreparedGameSession(root: root)
        #expect(session.terrain.terrain(19200) == nil)
        let path = root.appendingPathComponent("prepared_import.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["terrainSources"] = [edition == .macintosh11 ? "classicGraphics" : "graphics2"]
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        #expect(throws: (any Error).self) { try PreparedGameSession(root: root) }
    }
}
