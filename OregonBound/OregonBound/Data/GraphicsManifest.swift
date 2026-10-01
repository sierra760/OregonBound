import Foundation

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
    var image_path: String
    let width: Int
    let height: Int
    let mode: String
    let frame_index: Int
    let frame_count: Int
    let palette: ManifestPalette?
    var bounds: [Int]? = nil
    var diagnostics: [ManifestImageDiagnostic]? = nil
}

struct GraphicsManifest: Codable {
    let source_file: String
    let images: [ManifestImage]

    /// Numeric IDs are shared across resource types, including sidebar icons
    /// and monochrome panel artwork. A requested type must never fall back.
    func image(resource id: Int, type: String? = nil, frame: Int = 0) -> ManifestImage? {
        images.first {
            $0.resource.id == id && $0.frame_index == frame
                && (type == nil || $0.resource.type == type)
        }
    }

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


struct ManifestImageDiagnostic: Codable {
    let severity: String
    let code: String
    let message: String
}
