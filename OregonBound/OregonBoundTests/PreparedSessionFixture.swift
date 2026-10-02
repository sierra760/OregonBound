import Foundation
@testable import OregonBound

enum PreparedSessionFixture {
    static func make(at destination: URL? = nil, edition: GameEdition = .macintoshCD12,
                     schemaVersion: Int = 9, icons: Bool = false) throws -> URL {
        let root = destination ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = ExtractionOutput(root: root)
        let app: GameDataSourceRole = edition == .macintosh11 ? .classicApplication : .cdApplication
        var sources: [GameDataSourceRole: GameDataSourceCatalog.Candidate] = [:]
        for role in edition.requiredRoles {
            var records: [MacResource]
            switch role {
            case .classicApplication, .cdApplication: records = [.init(type: "Imag", id: 7, name: nil, attributes: 0, data: Data([0, 1])),
                .init(type: "CONF", id: 1000, name: nil, attributes: 0, data: ConfigurationDefaultsTests.fixture())]
            case .classicGraphics, .graphics2: records = [.init(type: "Imag", id: 7, name: nil, attributes: 0, data: Data([0, 1]))]
            case .graphics3: records = [.init(type: "Ima4", id: 7, name: nil, attributes: 0, data: Data([0, 1]))]
            default: records = []
            }
            if edition == .macintoshCD12 && role == app && schemaVersion >= 9 {
                records += [.init(type: "TEXT", id: 200, name: nil, attributes: 0, data: Data("Team\rSample\r".utf8)),
                            .init(type: "styl", id: 200, name: nil, attributes: 0, data: GameDataPreparationTests.styleScrap([0, 5]))]
                try output.write(records[records.count - 2].data, to: "runtime/about_text_200.bin")
                try output.write(records[records.count - 1].data, to: "runtime/about_styl_200.bin")
            }
            if icons && role == app {
                records += [.init(type: "ICON", id: 7, name: nil, attributes: 0, data: Data(repeating: 0, count: 128)),
                            .init(type: "cicn", id: 7, name: nil, attributes: 0, data: Data([0]))]
            }
            let fork = MacResourceFork(resources: records)
            let source = MacForkSource(displayName: role.rawValue, origin: "fixture", fileType: nil, creator: nil, dataFork: Data(), resourceFork: Data(role.rawValue.utf8))
            sources[role] = .init(source: source, fork: fork)
        }
        let catalog = try GameResourceCatalog(selection: .init(edition: edition, sources: sources, unrecognized: []))
        try output.writeJSON(catalog, to: "resource_catalog.json")
        try output.writeJSON(GameResourceLookup(catalog: catalog).index, to: "resource_lookup.json")
        var paths: [String: String] = [:]
        let graphicsRoles: [GameDataSourceRole] = edition == .macintosh11 ? [.classicApplication, .classicGraphics] : [.cdApplication, .graphics1, .graphics2, .graphics3, .graphics4]
        for role in graphicsRoles {
            var images: [ManifestImage] = []
            if [.classicApplication, .classicGraphics, .cdApplication, .graphics2, .graphics3].contains(role) {
                let type = role == .graphics3 ? "Ima4" : "Imag"
                let count = [.classicGraphics, .graphics2].contains(role) ? 2 : 1
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
            if icons && role == app {
                for type in ["ICON", "cicn"] {
                    let path = "images/\(type)/\(type.lowercased())_7.png"
                    images.append(.init(resource: .init(source_file: role.rawValue, type: type, id: 7,
                        name: "", raw_length: type == "ICON" ? 128 : 1), status: "ok", image_path: path,
                        width: 32, height: 32, mode: "RGBA", frame_index: 0, frame_count: 1, palette: nil))
                    try output.writePNG(.init(width: 32, height: 32, colorType: .rgba,
                        pixels: Array(repeating: 0, count: 32 * 32 * 4)), to: "sources/\(role.rawValue)/\(path)")
                }
            }
            let path = "sources/\(role.rawValue)/graphics_manifest.json"
            paths[role.rawValue] = path
            try output.writeJSON(GraphicsManifest(source_file: role.rawValue, images: images), to: path)
        }
        let rasterPath = "sources/\(app.rawValue)/raster_pictures.json"
        try output.writeJSON([ManifestImage](), to: rasterPath)
        let preferencesPath = "sources/\(app.rawValue)/preference_defaults.json"
        let configuration = ConfigurationDefaultsTests.fixture()
        try output.writeJSON(ConfigurationExtractor.Profile(schemaVersion: 1, edition: edition, role: app,
            resourceID: 1000, resourceSHA256: GameDataSourceCatalog.Candidate.digest(configuration),
            defaults: ConfigurationExtractor.parse(configuration)), to: preferencesPath)
        let manifest = GameDataPreparation.Manifest(schemaVersion: schemaVersion, edition: edition, preparedAt: Date(), catalogPath: "resource_catalog.json", lookupPath: "resource_lookup.json", preferencesPath: preferencesPath, graphics: paths, rasterPictures: [app.rawValue: rasterPath], soundSources: [], terrainSources: [], pendingResources: [], unrecognizedSources: [])
        try output.writeJSON(manifest, to: "prepared_import.json")
        return root
    }
}
