import Foundation
import Testing
@testable import OregonBound

struct PreparedGameSessionTests {
    @Test func monochromeUsesExplicitPairsTypedIconsAndNewPreparation() throws {
        let root = try PreparedSessionFixture.make(schemaVersion: 8, icons: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mono = try PreparedGameSession(root: root, colorMode: .monochrome)
        let color = try PreparedGameSession(root: root)
        #expect(mono.imageType == "Imag" && mono.colorMode.imageDepth == .monochrome)
        #expect(mono.colorMode.iconType == "ICON" && color.colorMode.iconType == "cicn")
        #expect(mono.colorMode.resource(monochrome: 129, color: 10129) == 129)
        #expect(color.colorMode.resource(monochrome: 129, color: 10129) == 10129)
        #expect(mono.colorMode.resource(monochrome: 20300, color: 20300) == 20300)
        #expect(mono.displayImage(monochromeID: 7, colorID: 7) != nil)
        #expect(mono.defaultGraphics.image(resource: 7, type: "ICON") != nil)
        #expect(mono.defaultGraphics.image(resource: 7, type: "cicn") == nil)
        #expect(mono.displayImage(monochromeID: 7, colorID: 999)?.resource.type == "Imag")
        #expect(color.displayImage(monochromeID: 7, colorID: 999) == nil)
        #expect(mono.displayImage(monochromeID: 999, colorID: 7) == nil)
        #expect(mono.displayImage(monochromeID: 7, colorID: 7, frame: 2) == nil)
        #expect(mono.sourceFingerprint == color.sourceFingerprint && mono.id != color.id)
        #expect(!PreparedGameSession.ColorMode.selectableModes.contains(.monochrome))
        let old = try PreparedSessionFixture.make()
        defer { try? FileManager.default.removeItem(at: old) }
        #expect(throws: (any Error).self) { try PreparedGameSession(root: old, colorMode: .monochrome) }
        let classic = try PreparedSessionFixture.make(edition: .macintosh11, schemaVersion: 8)
        defer { try? FileManager.default.removeItem(at: classic) }
        #expect(throws: (any Error).self) { try PreparedGameSession(root: classic, colorMode: .monochrome) }
    }

    @Test func schema8IconsStayTypedAndOutsideColorPresentation() throws {
        let root = try PreparedSessionFixture.make(schemaVersion: 8, icons: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for mode in [PreparedGameSession.ColorMode.color256, .color16] {
            let session = try PreparedGameSession(root: root, colorMode: mode)
            #expect(session.image(type: "ICON", id: 7)?.resource.source_file == "cdApplication")
            #expect(session.image(type: "ICON", id: 7)?.image_path == "sources/cdApplication/images/ICON/icon_7.png")
            #expect(session.image(type: "cicn", id: 7) != nil)
            #expect(session.displayImage(id: 7)?.resource.type == mode.imageType)
            #expect(!session.defaultGraphics.images.contains { $0.resource.type == "ICON" })
        }
    }

    @Test(arguments: [6, 7, 8]) func iconCompletenessIsVersioned(schema: Int) throws {
        let edition: GameEdition = schema == 6 ? .macintosh11 : .macintoshCD12
        let root = try PreparedSessionFixture.make(edition: edition, schemaVersion: schema, icons: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = edition == .macintosh11 ? "classicApplication" : "cdApplication"
        let path = root.appendingPathComponent("sources/\(app)/graphics_manifest.json")
        let manifest = try JSONDecoder().decode(GraphicsManifest.self, from: Data(contentsOf: path))
        let missing = GraphicsManifest(source_file: manifest.source_file,
            images: manifest.images.filter { $0.resource.type != "ICON" })
        try JSONEncoder().encode(missing).write(to: path)
        if schema == 8 {
            #expect(throws: (any Error).self) { try PreparedGameSession(root: root) }
        } else {
            let session = try PreparedGameSession(root: root)
            #expect(session.image(type: "ICON", id: 7) == nil)
        }
    }

    @Test func alternateColorSessionKeepsTypedIdentityAndNoFrameFallback() throws {
        let root = try PreparedSessionFixture.make(); defer { try? FileManager.default.removeItem(at: root) }
        let normal = try PreparedGameSession(root: root)
        let alternate = try PreparedGameSession(root: root, colorMode: .color16)
        #expect(normal.imageType == "Imag" && alternate.imageType == "Ima4")
        #expect(alternate.defaultGraphics.images.count == 1)
        #expect(alternate.displayImage(id: 7)?.resource.source_file == "graphics3")
        #expect(alternate.displayImage(id: 7, frame: 1) == nil)
        #expect(alternate.image(type: "Imag", id: 7, frame: 1) != nil)
        #expect(normal.sourceFingerprint == alternate.sourceFingerprint && normal.id != alternate.id)
        let classic = try PreparedSessionFixture.make(edition: .macintosh11)
        defer { try? FileManager.default.removeItem(at: classic) }
        #expect(throws: (any Error).self) { try PreparedGameSession(root: classic, colorMode: .color16) }
    }
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
    @Test(arguments: [GameEdition.macintosh11, .macintoshCD12])
    func requiresReimportOfUnconvertedAlternateColors(edition: GameEdition) throws {
        let root = try PreparedSessionFixture.make(edition: edition); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("prepared_import.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["schemaVersion"] = 6
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        if edition == .macintoshCD12 {
            #expect(throws: (any Error).self) { try PreparedGameSession(root: root) }
        } else { #expect(try PreparedGameSession(root: root).edition == .macintosh11) }
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
