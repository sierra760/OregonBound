import Foundation
import Testing
@testable import OregonBound

struct PreparedGameSessionTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = ExtractionOutput(root: root)
        let edition = GameEdition.macintoshCD12
        var sources: [GameDataSourceRole: GameDataSourceCatalog.Candidate] = [:]
        for role in edition.requiredRoles {
            let records: [MacResource]
            switch role {
            case .cdApplication: records = [.init(type: "Imag", id: 7, name: nil, attributes: 0, data: Data([0, 1])),
                .init(type: "CONF", id: 1000, name: nil, attributes: 0, data: ConfigurationDefaultsTests.fixture())]
            case .graphics2: records = [.init(type: "Imag", id: 7, name: nil, attributes: 0, data: Data([0, 1]))]
            case .graphics3: records = [.init(type: "Ima4", id: 7, name: nil, attributes: 0, data: Data([0, 1]))]
            default: records = []
            }
            let fork = MacResourceFork(resources: records)
            let source = MacForkSource(displayName: role.rawValue, origin: "fixture", fileType: nil, creator: nil, dataFork: Data(), resourceFork: Data(role.rawValue.utf8))
            sources[role] = .init(source: source, fork: fork)
        }
        let catalog = try GameResourceCatalog(selection: .init(edition: edition, sources: sources, unrecognized: []))
        try output.writeJSON(catalog, to: "resource_catalog.json")
        try output.writeJSON(GameResourceLookup(catalog: catalog).index, to: "resource_lookup.json")
        var paths: [String: String] = [:]
        for role in [GameDataSourceRole.cdApplication, .graphics1, .graphics2, .graphics3, .graphics4] {
            var images: [ManifestImage] = []
            if [.cdApplication, .graphics2, .graphics3].contains(role) {
                let type = role == .graphics3 ? "Ima4" : "Imag"
                let count = role == .graphics2 ? 2 : 1
                for frame in 0..<count {
                    let suffix = count > 1 ? String(format: "_%02d", frame) : ""
                    let path = "images/\(type)/\(type.lowercased())_7\(suffix).png"
                    var image = ManifestImage(resource: .init(source_file: role.rawValue, type: type, id: 7, name: "", raw_length: 2),
                        status: "ok", image_path: path, width: 1, height: 1, mode: "RGBA", frame_index: frame, frame_count: count, palette: nil)
                    image.bounds = [0, 0, 1, 1]
                    images.append(image)
                    try output.writePNG(.init(width: 1, height: 1, colorType: .rgba, pixels: [UInt8(frame), 0, 0, 255]), to: "sources/\(role.rawValue)/\(path)")
                }
            }
            let path = "sources/\(role.rawValue)/graphics_manifest.json"
            paths[role.rawValue] = path
            try output.writeJSON(GraphicsManifest(source_file: role.rawValue, images: images), to: path)
        }
        let rasterPath = "sources/cdApplication/raster_pictures.json"
        try output.writeJSON([ManifestImage](), to: rasterPath)
        let preferencesPath = "sources/cdApplication/preference_defaults.json"
        let configuration = ConfigurationDefaultsTests.fixture()
        try output.writeJSON(ConfigurationExtractor.Profile(schemaVersion: 1, edition: edition, role: .cdApplication,
            resourceID: 1000, resourceSHA256: GameDataSourceCatalog.Candidate.digest(configuration),
            defaults: ConfigurationExtractor.parse(configuration)), to: preferencesPath)
        let manifest = GameDataPreparation.Manifest(schemaVersion: 6, edition: edition, preparedAt: Date(), catalogPath: "resource_catalog.json", lookupPath: "resource_lookup.json", preferencesPath: preferencesPath, graphics: paths, rasterPictures: ["cdApplication": rasterPath], soundSources: [], terrainSources: [], pendingResources: [], unrecognizedSources: [])
        try output.writeJSON(manifest, to: "prepared_import.json")
        return root
    }
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
