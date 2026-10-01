import Foundation
import Testing
@testable import OregonBound

struct PreparedGameSessionTests {
    private func fixture() throws -> URL { try PreparedSessionFixture.make() }
    @Test func resolvesSourcesTypesFramesAndIndependentSessionIdentity() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let session = try PreparedGameSession(root: root)
        #expect(session.edition == .macintoshCD12)
        #expect(session.image(type: "Imag", id: 7, frame: 1)?.resource.source_file == "graphics2")
        #expect(session.image(type: "Ima4", id: 7, frame: 0)?.resource.source_file == "graphics3")
        #expect(session.image(type: "Imag", id: 7, frame: 0)?.bounds == [0, 0, 1, 1])
        #expect(session.image(type: "Imag", id: 7, frame: 0)?.image_path == "sources/graphics2/images/Imag/imag_7_00.png")
        #expect(session.graphics.images.count == 3)
        #expect(session.defaultGraphics.images.count == 2)
        #expect(session.image(type: "Imag", id: 7, frame: 2) == nil)
        #expect(try PreparedGameSession(root: root).id != session.id)
    }
    @Test(arguments: ["missing_frame", "duplicate", "source", "path", "missing_file", "index", "schema", "alias"])
    func rejectsInconsistentPreparedAssets(kind: String) throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("sources/graphics2/graphics_manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var images = try #require(object["images"] as? [[String: Any]])
        switch kind {
        case "alias": images[1]["image_path"] = images[0]["image_path"]
        case "missing_frame": images.removeLast()
        case "duplicate": images[1] = images[0]
        case "source":
            var resource = try #require(images[0]["resource"] as? [String: Any]); resource["source_file"] = "cdApplication"; images[0]["resource"] = resource
        case "path": images[0]["image_path"] = "../../outside.png"
        case "missing_file": try FileManager.default.removeItem(at: root.appendingPathComponent("sources/graphics2/images/Imag/imag_7_00.png"))
        case "index":
            let p = root.appendingPathComponent("resource_lookup.json")
            var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: p)) as? [String: Any]); value["entries"] = []
            try JSONSerialization.data(withJSONObject: value).write(to: p)
        default:
            let p = root.appendingPathComponent("prepared_import.json")
            var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: p)) as? [String: Any]); value["schemaVersion"] = 99
            try JSONSerialization.data(withJSONObject: value).write(to: p)
        }
        object["images"] = images
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        #expect(throws: (any Error).self) { try PreparedGameSession(root: root) }
    }
    @Test func cacheInvalidatesValuesAndMissesWhenSessionChanges() {
        let cache = SessionResourceCache<String, Int>()
        let first = UUID(), second = UUID()
        var loads = 0
        func load() -> Int? { loads += 1; return loads }
        #expect(cache.value(for: "image", session: first, load: load) == 1)
        #expect(cache.value(for: "image", session: first, load: load) == 1)
        #expect(cache.value(for: "absent", session: first, load: { nil }) == nil)
        #expect(cache.value(for: "absent", session: first, load: load) == nil)
        #expect(cache.value(for: "image", session: second, load: load) == 2)
        #expect(cache.value(for: "absent", session: second, load: load) == 3)
    }
    @Test(arguments: ["schemaVersion", "edition", "role", "resourceID", "resourceSHA256", "missing", "path"])
    func rejectsInvalidPreferenceProfile(field: String) throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("sources/cdApplication/preference_defaults.json")
        if field == "missing" {
            try FileManager.default.removeItem(at: path)
        } else if field == "path" {
            let manifest = root.appendingPathComponent("prepared_import.json")
            var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
            value["preferencesPath"] = "../../preference_defaults.json"
            try JSONSerialization.data(withJSONObject: value).write(to: manifest)
        } else {
            var value = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            let replacements: [String: Any] = ["schemaVersion": 2, "edition": GameEdition.macintosh11.rawValue,
                "role": "graphics2", "resourceID": 1001, "resourceSHA256": "wrong"]
            value[field] = replacements[field]
            try JSONSerialization.data(withJSONObject: value).write(to: path)
        }
        #expect(throws: (any Error).self) { try PreparedGameSession(root: root) }
    }
    @Test func storeCapturesMatchingProfileAndPreservesSavedPreferences() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let session = try PreparedGameSession(root: root)
        let base = root.appendingPathComponent("player")
        let store = JourneyStore(directory: base, edition: .macintoshCD12, session: session)
        var expected = OriginalPreferences.Configuration(defaults: session.preferenceDefaults)
        #expect(try store.preferences() == expected)
        #expect(try JourneyStore(directory: base, edition: .macintosh11, session: session).preferences() == .init())
        #expect(try JourneyStore(directory: base, edition: .macintoshCD12, defaultPreferences: .init(), session: session).preferences() == .init())
        // Once captured, a store does not reread mutable prepared files.
        try FileManager.default.removeItem(at: root.appendingPathComponent("sources/cdApplication/preference_defaults.json"))
        #expect(try store.preferences() == expected)
        expected.timing = .init(speed: .fast, huntTime: .seconds20)
        #expect(expected.changePassword(old: "Key", new: "Another", hint: "Saved") == nil)
        try store.savePreferences(expected)
        #expect(try JourneyStore(directory: base, edition: .macintoshCD12, session: session).preferences() == expected)
    }
}
