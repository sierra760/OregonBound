import Foundation

/// CD hunting terrain: two entry-side permissions, a signed rectangle count,
/// then absolute QuickDraw bounds used by the animal movement collision check.
enum TerrainExtractor {
    struct Obstacle: Codable {
        let top: Int
        let left: Int
        let bottom: Int
        let right: Int
    }
    struct Terrain: Codable {
        let resourceID: Int
        let leftEntryAllowed: Bool
        let rightEntryAllowed: Bool
        let obstacles: [Obstacle]
        enum CodingKeys: String, CodingKey {
            case resourceID = "resource_id", leftEntryAllowed = "left_entry_allowed"
            case rightEntryAllowed = "right_entry_allowed", obstacles
        }
    }

    static func parse(_ data: Data, resourceID: Int) throws -> Terrain {
        let source = ByteSource(data)
        let count = Int(try source.i16(4))
        guard count >= 0, data.count == 6 + count * 8 else {
            throw ReferenceDecodeError.value("Invalid TERR \(resourceID) rectangle count or payload length")
        }
        var obstacles: [Obstacle] = []
        for index in 0..<count {
            let rect = try source.rect(6 + index * 8)
            guard rect.width > 0, rect.height > 0 else {
                throw ReferenceDecodeError.value("Invalid TERR \(resourceID) rectangle \(index)")
            }
            obstacles.append(Obstacle(top: rect.top, left: rect.left, bottom: rect.bottom, right: rect.right))
        }
        return Terrain(resourceID: resourceID, leftEntryAllowed: try source.i16(0) != 0,
                       rightEntryAllowed: try source.i16(2) != 0, obstacles: obstacles)
    }

    static func extract(fork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in fork.resources(ofType: "TERR") {
            try output.writeJSON(parse(resource.data, resourceID: resource.id), to: "terrain/terr_\(resource.id).json")
        }
    }
}
