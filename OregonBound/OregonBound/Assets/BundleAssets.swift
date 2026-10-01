import Foundation
import OSLog

private let bundleLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "BundleAssets")

enum BundleAssets {
    static func loadManifest(root: URL? = GameData.root) -> GraphicsManifest? {
        if root == GameData.root, let session = GameData.preparedSession { return session.defaultGraphics }
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
