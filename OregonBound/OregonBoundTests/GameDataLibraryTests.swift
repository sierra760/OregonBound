import Foundation
import Testing
@testable import OregonBound

struct GameDataLibraryTests {
    enum Failure: Error { case prepare, publish }
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func install(_ library: GameDataLibrary, edition: GameEdition = .macintoshCD12) throws -> PreparedGameSession {
        try library.install(edition: edition) { _ = try PreparedSessionFixture.make(at: $0, edition: edition) }
    }

    @Test func reimportPreservesOldSessionAndSeparatesEditions() throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        #expect(try library.load(.macintoshCD12) == nil)
        let first = try install(library)
        let firstImage = try #require(first.image(type: "Imag", id: 7)).image_path
        let pixels = try Data(contentsOf: first.root.appendingPathComponent(firstImage))
        let classic = try install(library, edition: .macintosh11)
        let second = try install(library)
        #expect(first.root != second.root && first.id != second.id)
        #expect(first.sourceFingerprint == second.sourceFingerprint)
        #expect(classic.sourceFingerprint != first.sourceFingerprint)
        #expect(try Data(contentsOf: first.root.appendingPathComponent(firstImage)) == pixels)
        let restarted = GameDataLibrary(root: root)
        #expect(try restarted.load(.macintoshCD12)?.root == second.root)
        #expect(try restarted.load(.macintosh11)?.root == classic.root)
        #expect(try PreparedGameSession(root: first.root).sourceFingerprint == first.sourceFingerprint)
    }

    @Test(arguments: ["prepare", "invalid", "cancel", "publish", "edition"])
    func failedImportPreservesCurrentAndCleansOnlyItsGeneration(kind: String) throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        let previous = try install(library)
        let generations = previous.root.deletingLastPathComponent()
        let before = try FileManager.default.contentsOfDirectory(atPath: generations.path)
        var cancelled = false
        #expect(throws: (any Error).self) {
            try library.install(edition: .macintoshCD12, isCancelled: { cancelled }, publish: { data, url in
                if kind == "publish" { throw Failure.publish }
                try data.write(to: url, options: .atomic)
            }) { destination in
                if kind == "prepare" { throw Failure.prepare }
                _ = try PreparedSessionFixture.make(at: destination, edition: kind == "edition" ? .macintosh11 : .macintoshCD12)
                if kind == "invalid" { try FileManager.default.removeItem(at: destination.appendingPathComponent("prepared_import.json")) }
                if kind == "cancel" { cancelled = true }
            }
        }
        #expect(try library.load(.macintoshCD12)?.root == previous.root)
        #expect(try FileManager.default.contentsOfDirectory(atPath: generations.path) == before)
    }

    @Test(arguments: ["schema", "edition", "generation", "fingerprint", "symlink"])
    func rejectsInvalidInstalledRecord(kind: String) throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        let installed = try install(library)
        let recordURL = root.appendingPathComponent("macintosh-cd-1.2/current.json")
        if kind == "symlink" {
            let outside = folder(); defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.moveItem(at: installed.root, to: outside)
            try FileManager.default.createSymbolicLink(at: installed.root, withDestinationURL: outside)
            #expect(throws: (any Error).self) { try library.load(.macintoshCD12) }
            return
        }
        var record = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        switch kind {
        case "schema": record["schemaVersion"] = 99
        case "edition": record["edition"] = GameEdition.macintosh11.rawValue
        case "generation": record["generation"] = "../../outside"
        default: record["sourceFingerprint"] = "wrong"
        }
        try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
        #expect(throws: (any Error).self) { try library.load(.macintoshCD12) }
    }

    @Test func fingerprintUsesSortedRolesAndBytesRatherThanPaths() throws {
        func source(_ role: GameDataSourceRole, _ hash: String, _ origin: String) -> GameResourceCatalog.Source {
            .init(role: role, origin: origin, sha256: hash, length: 1)
        }
        let a = source(.classicApplication, "aaa", "one"), b = source(.classicGraphics, "bbb", "two")
        let first = GameSourceFingerprint.make(edition: .macintosh11, sources: [a, b])
        #expect(first == GameSourceFingerprint.make(edition: .macintosh11, sources: [b, source(.classicApplication, "aaa", "moved")]))
        #expect(first != GameSourceFingerprint.make(edition: .macintoshCD12, sources: [a, b]))
        #expect(first != GameSourceFingerprint.make(edition: .macintosh11, sources: [a, source(.classicGraphics, "ccc", "two")]))
        #expect(first != GameSourceFingerprint.make(edition: .macintosh11, sources: [a, b, source(.system, "ddd", "system")]))
    }

    @Test func overlappingPreparationsRetainBothPublishedGenerations() throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        var nested: PreparedGameSession?
        let lastPublished = try library.install(edition: .macintoshCD12) { destination in
            _ = try PreparedSessionFixture.make(at: destination)
            nested = try install(library)
            #expect(try library.load(.macintoshCD12)?.root == nested?.root)
        }
        #expect(try library.load(.macintoshCD12)?.root == lastPublished.root)
        let earlier = try #require(nested)
        #expect(try PreparedGameSession(root: earlier.root).sourceFingerprint == earlier.sourceFingerprint)
    }

    @Test func importRejectsEscapingEditionDirectoryBeforeWriting() throws {
        let root = folder(), outside = folder()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("macintosh-cd-1.2"), withDestinationURL: outside)
        #expect(throws: (any Error).self) { try install(GameDataLibrary(root: root)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func productionDirectoryReplacementRetainsStableRootOnReload() throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        let installed = try library.install(edition: .macintoshCD12) { destination in
            _ = try GameDataInstallation.run(destination: destination) {
                try PreparedSessionFixture.make(at: $0)
            }
        }
        #expect(installed.root.hasDirectoryPath)
        #expect(try library.load(.macintoshCD12)?.root == installed.root)
    }
}
