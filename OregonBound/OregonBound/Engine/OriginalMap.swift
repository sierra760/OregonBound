import Foundation

enum OriginalMap {
    struct Point: Equatable { var x: Int; var y: Int }
    struct Delta: Decodable { let dx: Int; let dy: Int }
    struct PathResource: Decodable { let points: [Delta] }
    // A5−2848, paired with the original distance table A5−2800.
    static let steps = [[4,0],[12,0],[7,0],[22,0],[6,0],[15,0],[6,0],
                        [8,3],[4,0],[7,8],[4,0],[14,0],[8,0],[11,0],
                        [8,12],[7,0],[10,7]]
    static let distances = [[102,0],[83,0],[119,0],[250,0],[86,0],[190,0],[102,0],
                            [57,125],[162,0],[144,0],[57,0],[182,0],[114,0],[160,0],
                            [55,125],[120,0],[100,0]]
    static func stepCount(_ leg: Int, flags: Int) -> Int {
        switch leg {
        case 7, 9: return steps[leg][flags & 1]
        case 8: return flags & 1 != 0 ? 0 : steps[leg][0]
        case 14: return steps[leg][flags & 2 != 0 ? 1 : 0]
        case 15: return flags & 2 != 0 ? 0 : steps[leg][0]
        case 16: return steps[leg][flags & 4 != 0 ? 1 : 0]
        default: return steps[leg][0]
        }
    }
    /// CODE6:2126 leaves D6 unchanged for a skipped fort; caller208c puts the
    /// path index in D6. Preserve that original quirk rather than substituting
    /// the actual journey leg distance. Its associated step count is zero.
    static func distance(_ leg: Int, flags: Int, path: Int) -> Int {
        switch leg {
        case 7: return distances[leg][flags & 1]
        case 8: return flags & 1 != 0 ? path : distances[leg][0]
        case 14: return distances[leg][flags & 2 != 0 ? 1 : 0]
        case 15: return flags & 2 != 0 ? path : distances[leg][0]
        default: return distances[leg][0]
        }
    }
    /// CODE6:1e5e/23a8, number of HVof offsets painted in this path group.
    static func paintedCount(path: Int, destination: Int, remaining: Int, flags: Int, count: Int) -> Int {
        let ranges = [(-1,6),(6,9),(6,9),(9,13),(13,15),(13,15),(15,16),(15,16)]
        let (lower, upper) = ranges[path]
        let previous = destination - 1
        if lower > previous { return 0 }
        if upper <= previous { return count }
        var result = 0
        if previous >= lower + 1 {
            for leg in (lower + 1)...previous { result += stepCount(leg, flags: flags) }
        }
        let length = distance(destination, flags: flags, path: path)
        result += (length - remaining) * stepCount(destination, flags: flags) / length
        return min(count, max(0, result))
    }
    static func paintedPoints(destination: Int, remaining: Int, miles: Int, flags: Int,
                              paths: [[Delta]]) -> [Point] {
        guard miles > 0, (-1...16).contains(destination), paths.count == 8 else { return [] }
        var point = Point(x: 230, y: 103) // global rect(294,192)-(296,194), map at64,89
        var result = [point]
        let chosen = [0, flags & 1 != 0 ? 1 : 2, 3, flags & 2 != 0 ? 4 : 5, flags & 4 != 0 ? 6 : 7]
        for path in chosen {
            let count = paintedCount(path: path, destination: destination, remaining: remaining,
                                     flags: flags, count: paths[path].count)
            for delta in paths[path].prefix(count) {
                point.x += delta.dx; point.y += delta.dy
                result.append(point)
            }
        }
        return result
    }
}
