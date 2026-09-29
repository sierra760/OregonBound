import Foundation
import OSLog

private let configLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "Config")

enum ConfigLoader {
    static func load<T: Decodable>(
        _ type: T.Type,
        resource: String,
        extension ext: String = "json",
        bundle: Bundle = .main
    ) throws -> T {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else {
            configLogger.error("Config load failed: \(resource).\(ext) not found in bundle")
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "\(resource).\(ext) not found in bundle"])
        }
        do {
            let data = try Data(contentsOf: url)
            let result = try JSONDecoder().decode(type, from: data)
            configLogger.info("Config loaded: \(resource).\(ext, privacy: .public)")
            return result
        } catch {
            configLogger.error("Config decode failed for \(resource).\(ext): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
