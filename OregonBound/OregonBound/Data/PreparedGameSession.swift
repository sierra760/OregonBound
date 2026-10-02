import Foundation

/// Read-only runtime view of a completed preparation. Its lifetime identity is
/// separate from its on-disk location, which can be reused by a later import.
/// Pending resources remain visible; loading is not full gameplay certification.
struct PreparedGameSession {
    enum ColorMode: String, CaseIterable {
        case color256, color16, monochrome
        static let selectableModes: [Self] = [.color256, .color16, .monochrome]
        var title: String {
            switch self {
            case .color256: return "256 colors"
            case .color16: return "16 colors"
            case .monochrome: return "Black and white"
            }
        }
        var imageType: String { self == .color16 ? "Ima4" : "Imag" }
        var iconType: String { self == .monochrome ? "ICON" : "cicn" }
        func resource(monochrome: Int, color: Int) -> Int {
            self == .monochrome ? monochrome : color
        }
        var imageDepth: GameResourceLookup.Depth {
            switch self {
            case .color256: return .color256
            case .color16: return .color16
            case .monochrome: return .monochrome
            }
        }
    }
    let colorMode: ColorMode
    var imageType: String { colorMode.imageType }

    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let detail): return "Invalid prepared game data: \(detail). Re-import the original files." }
        }
    }
    private struct Key: Hashable { let role: GameDataSourceRole; let type: String; let id: Int }
    let id = UUID()
    let root: URL
    let manifest: GameDataPreparation.Manifest
    let catalog: GameResourceCatalog
    let lookup: GameResourceLookup
    let graphics: GraphicsManifest
    let sounds: PreparedSoundLibrary
    let terrain: PreparedTerrainLibrary
    let aboutCredits: CDAboutCredits?
    let preferenceDefaults: ConfigurationExtractor.Defaults
    var edition: GameEdition { manifest.edition }
    var sourceFingerprint: String { GameSourceFingerprint.make(edition: edition, sources: catalog.sources) }
    var hasSystemResources: Bool { catalog.sources.contains { $0.role == .system } }

    /// A presentation view retains the selected family's type and source identity.
    /// Missing variants and frames never fall back to the other color family.
    var defaultGraphics: GraphicsManifest {
        GraphicsManifest(source_file: graphics.source_file, images: graphics.images.filter {
            switch $0.resource.type {
            case "ICON": return colorMode == .monochrome
            case "cicn": return colorMode != .monochrome
            case "Imag", "Ima4": return $0.resource.type == imageType
            default: return true
            }
        })
    }

    func displayImage(id: Int, frame: Int = 0) -> ManifestImage? {
        image(type: imageType, id: id, frame: frame)
    }

    /// Source image objects receive two independent IDs, including same-ID
    /// pairs. A missing selected family never falls back to the other ID.
    func displayImage(monochromeID: Int, colorID: Int, frame: Int = 0) -> ManifestImage? {
        displayImage(id: colorMode.resource(monochrome: monochromeID, color: colorID), frame: frame)
    }

    init(root: URL, colorMode: ColorMode = .color256) throws {
        self.colorMode = colorMode
        self.root = root.standardizedFileURL
        func read<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
            try JSONDecoder().decode(type, from: Data(contentsOf: PreparedResourceFile.url(root: root, path: path)))
        }
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(GameDataPreparation.Manifest.self,
            from: Data(contentsOf: PreparedResourceFile.url(root: root, path: "prepared_import.json")))
        guard (manifest.edition == .macintoshCD12 ? manifest.schemaVersion == 9 : [6, 7, 8, 9].contains(manifest.schemaVersion)), manifest.catalogPath == "resource_catalog.json",
              manifest.lookupPath == "resource_lookup.json" else { throw Failure.invalid("unsupported manifest schema or paths") }
        guard colorMode == .color256 || manifest.edition == .macintoshCD12 else {
            throw Failure.invalid("alternate color mode requires Macintosh CD 1.2")
        }
        guard colorMode != .monochrome || manifest.schemaVersion >= 8 else {
            throw Failure.invalid("black-and-white artwork is unavailable in this older import")
        }
        let catalog = try read(GameResourceCatalog.self, manifest.catalogPath)
        let roles = Set(catalog.sources.map(\.role))
        let required = Set(manifest.edition.requiredRoles)
        guard catalog.edition == manifest.edition, roles.count == catalog.sources.count,
              required.isSubset(of: roles), roles.subtracting(required).isSubset(of: [.system]),
              catalog.entries.allSatisfy({ roles.contains($0.role) }) else { throw Failure.invalid("edition/source mismatch") }
        let lookup = try GameResourceLookup(catalog: catalog)
        let storedIndex = try read(GameResourceLookup.Index.self, manifest.lookupPath)
        guard storedIndex.schemaVersion == lookup.index.schemaVersion,
              storedIndex.edition == lookup.index.edition,
              storedIndex.entries == lookup.index.entries else { throw Failure.invalid("resource lookup does not match catalog") }
        let app: GameDataSourceRole = manifest.edition == .macintosh11 ? .classicApplication : .cdApplication
        guard manifest.preferencesPath == "sources/\(app.rawValue)/preference_defaults.json" else {
            throw Failure.invalid("preference defaults path")
        }
        let preferences = try read(ConfigurationExtractor.Profile.self, manifest.preferencesPath)
        guard preferences.schemaVersion == 1, preferences.edition == manifest.edition,
              preferences.role == app, preferences.resourceID == 1000,
              let entry = catalog.entries.first(where: { $0.role == app && $0.type == "CONF" && $0.id == 1000 }),
              entry.length == 1108, entry.sha256 == preferences.resourceSHA256 else {
            throw Failure.invalid("preference defaults source")
        }
        aboutCredits = manifest.edition == .macintoshCD12 ? try CDAboutCredits.load(root: root, catalog: catalog) : nil
        preferenceDefaults = preferences.defaults
        let graphicsRoles: Set<GameDataSourceRole> = manifest.edition == .macintosh11
            ? [.classicApplication, .classicGraphics] : [.cdApplication, .graphics1, .graphics2, .graphics3, .graphics4]
        guard Set(manifest.graphics.keys) == Set(graphicsRoles.map(\.rawValue)),
              Set(manifest.rasterPictures.keys) == [app.rawValue] else { throw Failure.invalid("graphics source manifests") }
        let entries = Dictionary(uniqueKeysWithValues: catalog.entries.map { (Key(role: $0.role, type: $0.type, id: $0.id), $0) })
        var frames: [Key: [ManifestImage]] = [:]
        func add(_ image: ManifestImage, role: GameDataSourceRole, rootRelative: Bool) throws {
            let key = Key(role: role, type: image.resource.type, id: image.resource.id)
            guard let entry = entries[key], entry.disposition == .resource,
                  image.resource.source_file == role.rawValue, image.resource.raw_length == entry.length,
                  ["Imag", "Ima4", "cicn", "ICON", "PICT"].contains(key.type),
                  image.width > 0, image.height > 0, image.width <= 16384, image.height <= 16384,
                  image.width * image.height <= 16 * 1024 * 1024,
                  image.frame_count > 0, image.frame_index >= 0, image.frame_index < image.frame_count,
                  image.status == "ok" || (image.status == "partial" && image.diagnostics?.allSatisfy({
                      $0.severity == "info" || ($0.severity == "warning" && $0.code == "imag.palette_fallback")
                  }) == true) else { throw Failure.invalid("image metadata for \(role.rawValue)/\(key.type)/\(key.id)") }
            if key.type == "ICON" {
                guard entry.length == 128, image.width == 32, image.height == 32,
                      image.mode == "RGBA", image.frame_index == 0, image.frame_count == 1 else {
                    throw Failure.invalid("monochrome icon metadata")
                }
            }
            let prefix = "sources/\(role.rawValue)/"
            let localPath = GraphicsExtractor.imageRelativePath(type: key.type, id: key.id,
                frameIndex: image.frame_index, frameCount: image.frame_count)
            let expectedPath = rootRelative ? prefix + localPath : localPath
            guard image.image_path == expectedPath else { throw Failure.invalid("image path does not match resource/frame") }
            let path = prefix + localPath
            _ = try PreparedResourceFile.url(root: root, path: path)
            var qualified = image
            qualified.image_path = path
            frames[key, default: []].append(qualified)
        }
        for role in graphicsRoles {
            let path = "sources/\(role.rawValue)/graphics_manifest.json"
            guard manifest.graphics[role.rawValue] == path else { throw Failure.invalid("graphics manifest path") }
            let source = try read(GraphicsManifest.self, path)
            guard source.source_file == role.rawValue else { throw Failure.invalid("graphics manifest source") }
            for image in source.images { try add(image, role: role, rootRelative: false) }
        }
        let rasterPath = "sources/\(app.rawValue)/raster_pictures.json"
        guard manifest.rasterPictures[app.rawValue] == rasterPath else { throw Failure.invalid("raster manifest path") }
        for image in try read([ManifestImage].self, rasterPath) {
            guard image.resource.type == "PICT" else { throw Failure.invalid("non-picture in raster manifest") }
            try add(image, role: app, rootRelative: true)
        }
        var pending: Set<Key> = []
        for resource in manifest.pendingResources {
            let key = Key(role: resource.role, type: resource.type, id: resource.id)
            guard manifest.edition == .macintoshCD12, key.role == app, key.type == "PICT", key.id == 10256,
                  entries[key] != nil, frames[key] == nil, pending.insert(key).inserted,
                  resource.path == "sources/\(app.rawValue)/pending/PICT_10256.bin" else { throw Failure.invalid("unexpected pending resource") }
            _ = try PreparedResourceFile.url(root: root, path: resource.path)
        }
        for entry in catalog.entries where graphicsRoles.contains(entry.role) {
            // Schema8 adds complete ICON extraction. Earlier color preparations
            // remain usable without icons; a future monochrome mode needs8.
            guard (["Imag", "Ima4", "cicn", "PICT"].contains(entry.type)
                   || (manifest.schemaVersion >= 8 && entry.type == "ICON")),
                  !(entry.type == "PICT" && GraphicsExtractor.textPictureIds.contains(entry.id)) else { continue }
            let key = Key(role: entry.role, type: entry.type, id: entry.id)
            if entry.disposition == .emptyPlaceholder || pending.contains(key) { continue }
            guard let images = frames[key], let first = images.first,
                  images.count == first.frame_count,
                  images.allSatisfy({ $0.frame_count == first.frame_count }),
                  images.map(\.frame_index).sorted() == Array(0..<images.count) else {
                throw Failure.invalid("missing or duplicate image frames for \(entry.role.rawValue)/\(entry.type)/\(entry.id)")
            }
        }
        let audioRoles = Set(catalog.entries.filter { $0.type == "snd " && required.contains($0.role) }.map(\.role))
        guard audioRoles == Set(manifest.soundSources), audioRoles.count == manifest.soundSources.count else { throw Failure.invalid("sound source manifests") }
        let terrainRoles = Set(catalog.entries.filter { $0.type == "TERR" && required.contains($0.role) }.map(\.role))
        guard terrainRoles == Set(manifest.terrainSources), terrainRoles.count == manifest.terrainSources.count else {
            throw Failure.invalid("terrain source manifests")
        }
        terrain = try PreparedTerrainLibrary(root: root, lookup: lookup, terrainSources: manifest.terrainSources)
        let effective = frames.flatMap { key, images -> [ManifestImage] in
            lookup.resource(type: key.type, id: key.id)?.role == key.role ? images : []
        }.sorted { ($0.resource.type, $0.resource.id, $0.frame_index) < ($1.resource.type, $1.resource.id, $1.frame_index) }
        self.manifest = manifest
        self.catalog = catalog
        self.lookup = lookup
        graphics = GraphicsManifest(source_file: manifest.edition.rawValue, images: effective)
        sounds = try PreparedSoundLibrary(root: root, lookup: lookup, soundSources: manifest.soundSources)
    }

    func image(type: String, id: Int, frame: Int = 0) -> ManifestImage? {
        graphics.images.first { $0.resource.type == type && $0.resource.id == id && $0.frame_index == frame }
    }

}

enum PreparedResourceFile {
    /// Containment includes symlink resolution, not just textual path prefixes.
    static func url(root: URL, path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\") else { throw PreparedGameSession.Failure.invalid("relative resource path") }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/"),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw PreparedGameSession.Failure.invalid("missing or escaping resource \(path)")
        }
        return url
    }
}
