import Foundation

/// Validated, source-qualified extraction used while building edition-aware
/// playback. A preparation is not an activated session or a claim that every
/// original resource has a native renderer; pending resources are explicit.
enum GameDataPreparation {
    struct PendingResource: Codable {
        let role: GameDataSourceRole
        let type: String
        let id: Int
        let path: String
        let reason: String
    }
    struct Manifest: Codable {
        let schemaVersion: Int
        let edition: GameEdition
        let preparedAt: Date
        let catalogPath: String
        let lookupPath: String
        let preferencesPath: String
        let graphics: [String: String]
        let rasterPictures: [String: String]
        let soundSources: [GameDataSourceRole]
        let terrainSources: [GameDataSourceRole]
        let pendingResources: [PendingResource]
        let unrecognizedSources: [String]
    }
    struct Report {
        let root: URL
        let manifest: Manifest
    }

    static func run(sources: [URL], destination: URL, progress: (String) -> Void,
                    isCancelled: () -> Bool = { false }) throws -> Report {
        let candidates = try GameDataSourceCatalog.read(sources, progress: progress)
        let selected = try GameDataSourceCatalog.select(candidates)
        return try run(selection: selected, destination: destination, progress: progress, isCancelled: isCancelled)
    }

    static func run(selection: GameDataSourceCatalog.Selection, destination: URL,
                    progress: (String) -> Void, isCancelled: () -> Bool = { false }) throws -> Report {
        try GameSourceRequirements.validate(selection)
        let catalog = try GameResourceCatalog(selection: selection)
        let lookup = try GameResourceLookup(catalog: catalog)
        let appRole: GameDataSourceRole = selection.edition == .macintosh11 ? .classicApplication : .cdApplication
        guard let app = selection.sources[appRole] else { throw GameDataSourceCatalog.Failure.missing([appRole]) }
        try TextResourceExtractors.validate(app.fork)
        guard let configuration = app.fork.resources.first(where: { $0.type == "CONF" && $0.id == 1000 }) else {
            throw ReferenceDecodeError.value("Missing application CONF1000")
        }
        let preferences = try ConfigurationExtractor.Profile(schemaVersion: 1, edition: selection.edition,
            role: appRole, resourceID: 1000, resourceSHA256: GameDataSourceCatalog.Candidate.digest(configuration.data),
            defaults: ConfigurationExtractor.parse(configuration.data))
        return try GameDataInstallation.run(destination: destination, isCancelled: isCancelled) { staging in
            let output = ExtractionOutput(root: staging)
            func step(_ message: String, _ work: () throws -> Void) throws {
                if isCancelled() { throw GameDataInstallation.Failure.cancelled }
                progress(message)
                try work()
            }
            var graphics: [String: String] = [:]
            var rasterPictures: [String: String] = [:]
            var soundSources: [GameDataSourceRole] = []
            var terrainSources: [GameDataSourceRole] = []
            var pending: [PendingResource] = []
            let graphicsRoles: [GameDataSourceRole] = selection.edition == .macintosh11
                ? [.classicGraphics] : [.graphics1, .graphics2, .graphics3, .graphics4]
            let paletteRole: GameDataSourceRole = selection.edition == .macintosh11 ? .classicGraphics : .graphics2
            guard let paletteFork = selection.sources[paletteRole]?.fork else { throw GameDataSourceCatalog.Failure.missing([paletteRole]) }
            let palette = try ImagDecoder.fallbackPalette(from: paletteFork)
            let context = GraphicsExtractor.PaletteContext(bytes: palette.palette, source: palette.source)
            for role in graphicsRoles + [appRole] {
                guard let candidate = selection.sources[role] else { throw GameDataSourceCatalog.Failure.missing([role]) }
                let relative = "sources/\(role.rawValue)"
                let sourceOutput = ExtractionOutput(root: output.url(relative))
                let fork = role == appRole
                    ? MacResourceFork(resources: candidate.fork.resources.filter { $0.type == "Imag" || $0.type == "cicn" })
                    : candidate.fork
                let placeholders = Set(catalog.entries.filter { $0.role == role && $0.disposition == .emptyPlaceholder }
                    .map { GameDataSourceCatalog.ResourceIdentity(type: $0.type, id: $0.id) })
                try step("Decoding \(role.title) graphics…") {
                    _ = try GraphicsExtractor.extract(colorFork: fork, into: sourceOutput, sourceName: role.rawValue,
                                                      paletteContext: context, expectedCounts: [], emptyPlaceholders: placeholders, strict: true)
                }
                graphics[role.rawValue] = relative + "/graphics_manifest.json"
            }
            try step("Decoding edition text and fonts…") {
                try TextResourceExtractors.extractAll(trailFork: app.fork, into: output,
                                                      originSourceFile: appRole.rawValue, edition: selection.edition)
                _ = try BitmapFontExtractor.extractGameFonts(trailFork: app.fork, into: output,
                                                             sourceName: appRole.rawValue, sourceSHA256: app.sha256)
                try GraphicsExtractor.extractTextPictures(trailFork: app.fork, into: output)
                try RuntimeResourceExtractor.extract(trailFork: app.fork, into: output)
            }
            for role in selection.edition.requiredRoles {
                guard let candidate = selection.sources[role], candidate.fork.contains("snd ") else { continue }
                try step("Decoding \(role.title) audio…") {
                    _ = try SoundExtractor.extractSounds(trailFork: candidate.fork,
                            into: ExtractionOutput(root: output.url("sources/\(role.rawValue)")), strict: true, includeMetadata: true)
                }
                soundSources.append(role)
            }
            for role in selection.edition.requiredRoles {
                guard let candidate = selection.sources[role], candidate.fork.contains("TERR") else { continue }
                try step("Decoding \(role.title) hunting terrain…") {
                    try TerrainExtractor.extract(fork: candidate.fork,
                        into: ExtractionOutput(root: output.url("sources/\(role.rawValue)")))
                }
                terrainSources.append(role)
            }
            // Keep undecoded pictures explicit instead of replacing them with a
            // platform fallback or treating unknown opcodes as a blank picture.
            var pictures: [DecodedImage] = []
            for resource in app.fork.resources where resource.type == "PICT" && !GraphicsExtractor.textPictureIds.contains(resource.id) {
                try step("Decoding application picture \(resource.id)…") {
                    var decoded = PICTDecoder.convert(resource: GraphicsExtractor.resourceInfo(resource, sourceFile: appRole.rawValue), data: resource.data)
                    if decoded.status == .ok, let image = decoded.image {
                        let path = "sources/\(appRole.rawValue)/images/PICT/pict_\(resource.id).png"
                        try output.writePNG(image, to: path)
                        decoded.imagePath = path
                        pictures.append(decoded)
                    } else {
                        guard selection.edition == .macintoshCD12, resource.id == 10256,
                              decoded.diagnostics.contains(where: { $0.code == "pict.unsupported_encoding" }) else {
                            throw GraphicsExtractor.Failure.incomplete(decoded.diagnostics.map(\.message).joined(separator: "; "))
                        }
                        let path = "sources/\(appRole.rawValue)/pending/PICT_\(resource.id).bin"
                        try output.write(resource.data, to: path)
                        pending.append(PendingResource(role: appRole, type: resource.type, id: resource.id, path: path,
                            reason: decoded.diagnostics.map(\.message).joined(separator: "; ")))
                    }
                }
            }
            let picturesPath = "sources/\(appRole.rawValue)/raster_pictures.json"
            try output.writeJSON(pictures, to: picturesPath)
            rasterPictures[appRole.rawValue] = picturesPath
            if let system = selection.sources[.system] {
                try step("Decoding optional System resources…") {
                    _ = try BitmapFontExtractor.extractSystemFonts(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256)
                    try SystemControlsExtractor.extractAll(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256)
                }
            }
            try output.writeJSON(catalog, to: "resource_catalog.json")
            try output.writeJSON(lookup.index, to: "resource_lookup.json")
            let preferencesPath = "sources/\(appRole.rawValue)/preference_defaults.json"
            try output.writeJSON(preferences, to: preferencesPath)
            let manifest = Manifest(schemaVersion: 6, edition: selection.edition, preparedAt: Date(),
                                    catalogPath: "resource_catalog.json", lookupPath: "resource_lookup.json", preferencesPath: preferencesPath, graphics: graphics, rasterPictures: rasterPictures, soundSources: soundSources, terrainSources: terrainSources,
                                    pendingResources: pending, unrecognizedSources: selection.unrecognized.map { $0.source.origin })
            try output.writeJSON(manifest, to: "prepared_import.json")
            return Report(root: destination, manifest: manifest)
        }
    }
}
