import Foundation

/// Immutable published generations. Re-import updates a small edition record;
/// old sessions retain their directories until an explicit future cleanup.
struct GameDataLibrary {
    struct Record: Codable {
        let schemaVersion: Int
        let edition: GameEdition
        let generation: UUID
        let sourceFingerprint: String
    }
    enum Failure: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let reason): return "Invalid installed game data: \(reason). Re-import the original files." }
        }
    }
    let root: URL
    static var defaultRoot: URL {
        // The legacy importer replaces GameData; generations must be siblings.
        GameData.storageDirectory.deletingLastPathComponent().appendingPathComponent("Installations", isDirectory: true)
    }
    private static let publicationLock = NSLock()

    init(root: URL = Self.defaultRoot) {
        self.root = URL(fileURLWithPath: root.path, isDirectory: true).standardizedFileURL
    }

    func selection() throws -> GameDataSelection? {
        let url = try contained("selection.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try PreparedResourceFile.url(root: root, path: "selection.json")
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65536 else {
            throw Failure.invalid("selection record size")
        }
        return try JSONDecoder().decode(GameDataSelection.self, from: Data(contentsOf: file))
    }

    func select(_ selection: GameDataSelection) throws {
        let url = try contained("selection.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(selection).write(to: url, options: .atomic)
    }

    func importSources(_ sources: [URL], progress: (String) -> Void,
                       isCancelled: () -> Bool = { false }) throws -> PreparedGameSession {
        if isCancelled() { throw GameDataInstallation.Failure.cancelled }
        let candidates = try GameDataSourceCatalog.read(sources, progress: progress)
        let selection = try GameDataSourceCatalog.select(candidates)
        return try install(edition: selection.edition, isCancelled: isCancelled) { destination in
            _ = try GameDataPreparation.run(selection: selection, destination: destination,
                                           progress: progress, isCancelled: isCancelled)
        }
    }

    /// Internal preparation/publication seams also allow failure-path tests.
    /// The callback writes only the provided, unpublished destination.
    func install(edition: GameEdition, isCancelled: () -> Bool = { false },
                 publish: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
                 prepare: (URL) throws -> Void) throws -> PreparedGameSession {
        if isCancelled() { throw GameDataInstallation.Failure.cancelled }
        let generation = UUID()
        let destination = try contained("\(edition.rawValue)/generations/\(generation.uuidString)", isDirectory: true)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw Failure.invalid("generation already exists") }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        var published = false
        defer { if !published { try? manager.removeItem(at: destination) } }
        try prepare(destination)
        if isCancelled() { throw GameDataInstallation.Failure.cancelled }
        let session = try PreparedGameSession(root: destination)
        guard session.edition == edition else { throw Failure.invalid("prepared edition mismatch") }
        let record = Record(schemaVersion: 1, edition: edition, generation: generation,
                            sourceFingerprint: session.sourceFingerprint)
        let data = try JSONEncoder().encode(record)
        Self.publicationLock.lock()
        defer { Self.publicationLock.unlock() }
        if isCancelled() { throw GameDataInstallation.Failure.cancelled }
        let recordURL = try contained("\(edition.rawValue)/current.json")
        try publish(data, recordURL)
        published = true
        return session
    }

    /// Missing edition is nil; an invalid installed record is an actionable error.
    /// Reading does not activate or migrate a running game.
    func load(_ edition: GameEdition, colorMode: PreparedGameSession.ColorMode = .color256) throws -> PreparedGameSession? {
        let relative = "\(edition.rawValue)/current.json"
        let recordURL = try contained(relative)
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let file = try PreparedResourceFile.url(root: root, path: relative)
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65536 else {
            throw Failure.invalid("installation record size")
        }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
        guard record.schemaVersion == 1, record.edition == edition else { throw Failure.invalid("installation record edition or version") }
        let location = try contained("\(edition.rawValue)/generations/\(record.generation.uuidString)", isDirectory: true)
        let session = try PreparedGameSession(root: location, colorMode: colorMode)
        guard session.edition == edition, session.sourceFingerprint == record.sourceFingerprint else {
            throw Failure.invalid("installation source identity")
        }
        return session
    }

    private func contained(_ relative: String, isDirectory: Bool = false) throws -> URL {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        // Resolving an entire path with a missing tail does not reliably resolve
        // existing parent symlinks. Check each component before creating anything.
        let components = relative.split(separator: "/")
        var location = base
        for (index, component) in components.enumerated() {
            location.appendPathComponent(String(component), isDirectory: index < components.count - 1 || isDirectory)
            if (try? location.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Failure.invalid("symbolic link in installation path")
            }
            let resolved = location.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(base.path + "/") else { throw Failure.invalid("escaping installation path") }
        }
        return location.standardizedFileURL
    }
}

enum GameDataSelection: Hashable, Identifiable, Codable {
    case installed(GameEdition)
    case legacyClassic

    var id: String {
        switch self { case .installed(let edition): return edition.rawValue; case .legacyClassic: return "legacy" }
    }
    var title: String {
        switch self { case .installed(let edition): return edition.title; case .legacyClassic: return "The Oregon Trail (existing classic import)" }
    }
    private enum CodingKeys: CodingKey { case schemaVersion, source, edition }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == 1 else { throw GameDataLibrary.Failure.invalid("selection version") }
        let edition = try values.decode(GameEdition.self, forKey: .edition)
        switch try values.decode(String.self, forKey: .source) {
        case "installed": self = .installed(edition)
        case "legacy" where edition == .macintosh11: self = .legacyClassic
        default: throw GameDataLibrary.Failure.invalid("selected data source")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schemaVersion)
        switch self {
        case .installed(let edition):
            try values.encode("installed", forKey: .source); try values.encode(edition, forKey: .edition)
        case .legacyClassic:
            try values.encode("legacy", forKey: .source); try values.encode(GameEdition.macintosh11, forKey: .edition)
        }
    }
}

enum GameSourceFingerprint {
    /// Versioned, ordered inputs; resource-fork bytes determine each SHA-256.
    /// Origins, timestamps and runtime session UUIDs deliberately do not contribute.
    static func make(edition: GameEdition, sources: [GameResourceCatalog.Source]) -> String {
        // Role names and hex digests cannot contain the field/record delimiters.
        let fields = sources.sorted { $0.role.rawValue < $1.role.rawValue }
            .map { "\($0.role.rawValue):\($0.sha256)" }.joined(separator: "\n")
        return GameDataSourceCatalog.Candidate.digest(Data("OregonBoundSources1\n\(edition.rawValue)\n\(fields)".utf8))
    }
}
