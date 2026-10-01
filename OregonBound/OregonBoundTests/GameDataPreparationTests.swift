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
}
