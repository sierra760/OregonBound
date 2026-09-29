import Foundation
import OSLog

private let bundleLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "BundleAssets")

struct ManifestResource: Codable {
    let source_file: String
    let type: String
    let id: Int
    let name: String
    let raw_length: Int
}

struct ManifestPalette: Codable {
    let source: String
    let entry_count: Int
}

struct ManifestImage: Codable {
    let resource: ManifestResource
    let status: String
    let image_path: String
    let width: Int
    let height: Int
    let mode: String
    let frame_index: Int
    let frame_count: Int
    let palette: ManifestPalette?
}

struct GraphicsManifest: Codable {
    let source_file: String
    let images: [ManifestImage]

    func images(forResourceId id: Int) -> [ManifestImage] {
        images.filter { $0.resource.id == id }
              .sorted { $0.frame_index < $1.frame_index }
    }

    func images(ofType type: String) -> [ManifestImage] {
        images.filter { $0.resource.type == type }
    }

    func firstImage(ofType type: String, resourceId id: Int) -> ManifestImage? {
        images(forResourceId: id).first { $0.resource.type == type }
    }
}

enum BundleAssets {
    static func loadManifest(root: URL? = GameData.root) -> GraphicsManifest? {
        guard let url = root?.appendingPathComponent("graphics_manifest.json"),
              FileManager.default.fileExists(atPath: url.path) else {
            bundleLogger.error("Graphics manifest missing: no imported game data")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(GraphicsManifest.self, from: data)
            return manifest
        } catch {
            bundleLogger.error("Bundle manifest decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    static func validateManifest(root: URL? = GameData.root) -> Int {
        guard let manifest = loadManifest(root: root) else { return 0 }
        let count = manifest.images.count
        bundleLogger.info("Bundle manifest OK: \(count, privacy: .public) images")
        return count
    }
}
