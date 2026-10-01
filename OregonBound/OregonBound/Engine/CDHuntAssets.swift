import Foundation

/// Geometry and terrain captured before a CD hunt starts. Resource IDs remain
/// canonical color IDs internally; the binding selects the requested art family.
struct CDHuntAssets {
    typealias Rect = OriginalHuntSession.Rect
    let frames: [Int: [Rect]]
    let terrains: [Int: TerrainExtractor.Terrain]
    let monochrome: Bool

    init(frames: [Int: [Rect]], terrains: [Int: TerrainExtractor.Terrain], monochrome: Bool) {
        self.frames = frames; self.terrains = terrains; self.monochrome = monochrome
    }
    init(session: PreparedGameSession, monochrome: Bool = false) throws {
        guard session.edition == .macintoshCD12 else { throw PreparedGameSession.Failure.invalid("CD hunting edition") }
        var frames: [Int: [Rect]] = [:]
        var terrains: [Int: TerrainExtractor.Terrain] = [:]
        func load(_ resource: Int, count: Int) throws {
            let id = resource - (monochrome ? 10000 : 0)
            frames[resource] = try (0..<count).map { index in
                guard let image = session.displayImage(id: id,frame: index), image.frame_count == count,
                      let bounds = image.bounds, bounds.count == 4,
                      bounds.allSatisfy({ (-32768...32767).contains($0) }),
                      bounds[2]-bounds[0] == image.height, bounds[3]-bounds[1] == image.width else {
                    throw PreparedGameSession.Failure.invalid("CD hunt image geometry \(id)/\(index)")
                }
                return Rect(x: bounds[1],y: bounds[0],width: image.width,height: image.height)
            }
        }
        try load(19160,count: 20)
        for habitat in 0..<10 {
            for view in 0..<3 {
                let id = 19200+10*habitat+view
                guard let terrain = session.terrain.terrain(id) else {
                    throw PreparedGameSession.Failure.invalid("CD hunt terrain \(id)")
                }
                terrains[id] = terrain
                try load(id,count: 1); try load(id+3,count: 1)
            }
        }
        for species in 0..<11 {
            for offset in (species == 10 ? [0] : [0,200,300]) {
                try load(19161+species+offset,count: CDHuntAnimal.profiles[species].lastFrame+1)
            }
        }
        self.init(frames: frames,terrains: terrains,monochrome: monochrome)
    }
    func resource(_ canonical: Int) -> Int { canonical - (monochrome ? 10000 : 0) }
    func bounds(_ resource: Int, _ frame: Int = 0) -> Rect { frames[resource]![frame] }
}
