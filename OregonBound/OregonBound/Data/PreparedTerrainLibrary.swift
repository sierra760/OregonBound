import Foundation

/// Captures validated terrain for one immutable installation. Lookup resolves
/// the source before reading; a missing selected resource never exposes an
/// application's lower-priority resource or another installation's terrain.
struct PreparedTerrainLibrary {
    private let terrains: [Int: TerrainExtractor.Terrain]

    init(root: URL, lookup: GameResourceLookup, terrainSources: [GameDataSourceRole]) throws {
        let sources = Set(terrainSources)
        guard sources.count == terrainSources.count,
              sources.isSubset(of: Set(lookup.index.edition.requiredRoles)) else {
            throw PreparedGameSession.Failure.invalid("terrain sources")
        }
        var loaded: [Int: TerrainExtractor.Terrain] = [:]
        for entry in lookup.index.entries where entry.type == "TERR" && sources.contains(entry.role) {
            let path = "sources/\(entry.role.rawValue)/terrain/terr_\(entry.id).json"
            let data = try Data(contentsOf: PreparedResourceFile.url(root: root,path: path))
            let terrain = try JSONDecoder().decode(TerrainExtractor.Terrain.self,from: data)
            guard terrain.resourceID == entry.id, (-32768...32767).contains(entry.id),
                  entry.disposition == .resource, terrain.obstacles.count <= 32767,
                  entry.length == 6 + terrain.obstacles.count * 8,
                  terrain.obstacles.allSatisfy({ rect in
                      [rect.top,rect.left,rect.bottom,rect.right].allSatisfy { (-32768...32767).contains($0) }
                          && rect.top < rect.bottom && rect.left < rect.right
                  }) else {
                throw PreparedGameSession.Failure.invalid("terrain metadata for \(entry.role.rawValue)/\(entry.id)")
            }
            loaded[entry.id] = terrain
        }
        terrains = loaded
    }

    func terrain(_ id: Int) -> TerrainExtractor.Terrain? { terrains[id] }
}
