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
        let graphics: [String: String]
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
        return try GameDataInstallation.run(destination: destination, isCancelled: isCancelled) { staging in
            let output = ExtractionOutput(root: staging)
            func step(_ message: String, _ work: () throws -> Void) throws {
                if isCancelled() { throw GameDataInstallation.Failure.cancelled }
                progress(message)
                try work()
            }
            var graphics: [String: String] = [:]
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
                            into: ExtractionOutput(root: output.url("sources/\(role.rawValue)")), strict: true)
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
            // Retain data whose native interpretation is still being recovered.
            // These entries cannot be mistaken for decoded/verified graphics.
            for role in selection.edition.requiredRoles {
                guard let candidate = selection.sources[role] else { continue }
                for resource in candidate.fork.resources {
                    let deferredPicture = role == appRole && resource.type == "PICT" && !GraphicsExtractor.textPictureIds.contains(resource.id)
                    guard deferredPicture else { continue }
                    let path = "sources/\(role.rawValue)/pending/\(resource.type)_\(resource.id).bin"
                    try output.write(resource.data, to: path)
                    pending.append(PendingResource(role: role, type: resource.type, id: resource.id, path: path,
                                                  reason: "Native raster PICT decoding pending"))
                }
            }
            if let system = selection.sources[.system] {
                try step("Decoding optional System resources…") {
                    _ = try BitmapFontExtractor.extractSystemFonts(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256)
                    try SystemControlsExtractor.extractAll(systemFork: system.fork, into: output, resourceForkSHA256: system.sha256)
                }
            }
            try output.writeJSON(catalog, to: "resource_catalog.json")
            try output.writeJSON(lookup.index, to: "resource_lookup.json")
            let manifest = Manifest(schemaVersion: 3, edition: selection.edition, preparedAt: Date(),
                                    catalogPath: "resource_catalog.json", lookupPath: "resource_lookup.json", graphics: graphics, soundSources: soundSources, terrainSources: terrainSources,
                                    pendingResources: pending, unrecognizedSources: selection.unrecognized.map { $0.source.origin })
            try output.writeJSON(manifest, to: "prepared_import.json")
            return Report(root: destination, manifest: manifest)
        }
    }
}
