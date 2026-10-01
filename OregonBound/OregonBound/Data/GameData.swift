import Foundation
import OSLog

private let dataLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "GameData")

/// Locates the imported original game data. The app ships no MECC or Apple
/// assets: everything under `root` is decoded at import time from files the
/// player supplies, in the same layout as the reference Python pipeline.
enum GameData {
    /// Bump when the on-disk layout or any decoder output changes so stale
    /// imports are redone.
    static let layoutVersion = 3
    static let manifestName = "import.json"
    static let environmentOverride = "OREGON_BOUND_DATA"

    struct ImportManifest: Codable {
        struct Source: Codable {
            let role: String
            let origin: String
            let sha256: String
            let length: Int
        }
        var layoutVersion: Int
        var importedAt: Date
        var sources: [Source]
        var hasSystemResources: Bool
    }

    /// Folder holding the current import, or nil until an import has completed.
    private(set) static var root: URL? = resolveRoot()

    static var isReady: Bool { root != nil }

    static var manifest: ImportManifest? {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent(manifestName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ImportManifest.self, from: data)
    }

    /// Whether the System 7.0 fonts and control artwork were part of the import.
    static var hasSystemResources: Bool { manifest?.hasSystemResources ?? false }

    /// Application Support location shared by the app and its test bundle.
    static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("OregonBound", isDirectory: true).appendingPathComponent("GameData", isDirectory: true)
    }

    static func url(forResource name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        guard let root else { return nil }
        var url = root
        if let subdirectory { url.appendPathComponent(subdirectory, isDirectory: true) }
        url.appendPathComponent("\(name).\(ext)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A path relative to the data root, as recorded in `graphics_manifest.json`.
    static func resourceURL(_ relativePath: String) -> URL? {
        guard let root, !relativePath.hasPrefix("/"), !relativePath.contains("..") else { return nil }
        return root.appendingPathComponent(relativePath)
    }

    /// Adopt a freshly completed import.
    static func activate(_ location: URL) {
        root = location
        dataLogger.info("Game data active at \(location.path, privacy: .public)")
    }

    static func resolveRoot() -> URL? {
        if let override = ProcessInfo.processInfo.environment[environmentOverride], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("graphics_manifest.json").path) {
                dataLogger.info("Using \(environmentOverride, privacy: .public) at \(url.path, privacy: .public)")
                return url
            }
            dataLogger.error("\(environmentOverride, privacy: .public) is set but has no graphics_manifest.json: \(url.path, privacy: .public)")
            return nil
        }
        let stored = storageDirectory
        guard let data = try? Data(contentsOf: stored.appendingPathComponent(manifestName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(ImportManifest.self, from: data) else { return nil }
        guard manifest.layoutVersion == layoutVersion else {
            dataLogger.notice("Stored import uses layout \(manifest.layoutVersion); \(layoutVersion) required. Re-import needed.")
            return nil
        }
        return stored
    }

    static func loadJSON<T: Decodable>(_ type: T.Type, name: String, subdirectory: String? = nil) -> T? {
        guard let url = url(forResource: name, withExtension: "json", subdirectory: subdirectory),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
