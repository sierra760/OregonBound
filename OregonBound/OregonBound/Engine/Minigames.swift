import Foundation

struct HuntAnimal: Identifiable, Equatable {
    let id: Int
    let species: Int
    var x: Double
    var y: Double
    let speed: Double
    var hit = false
    static let resources = [19161, 19162, 19163, 19164, 19165, 19166, 19167]
    static let weights = [800, 100, 5, 2, 200, 200, 80]
    var resource: Int { Self.resources[species] }
    var weight: Int { Self.weights[species] }
    var radius: Double { species == 2 || species == 3 ? 12 : 22 }
}

struct HuntSession {
    private(set) var animals: [HuntAnimal] = []
    private(set) var shots = 0
    private(set) var food = 0
    private(set) var elapsed = 0.0
    let ammunition: Int
    let duration: Double
    private var randomState: UInt32
    private var spawnClock = 0.0
    private var nextID = 0
    var finished: Bool { elapsed >= duration || shots >= ammunition }
    var remaining: Int { max(0, Int(ceil(duration - elapsed))) }

    init(ammunition: Int, duration: Double, seed: UInt32) {
        self.ammunition = max(0, ammunition)
        self.duration = max(1, duration)
        randomState = seed
    }

    mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !finished else { return }
        var left = min(seconds, duration - elapsed)
        while left > 0 {
            let dt = min(left, 0.05)
            elapsed += dt; left -= dt; spawnClock += dt
            for i in animals.indices { animals[i].x += animals[i].hit ? 0 : animals[i].speed * dt }
            let clearHits = animals.count > 8
            animals.removeAll { $0.x < -35 || $0.x > 535 || ($0.hit && clearHits) }
            if spawnClock >= 0.9 {
                spawnClock = 0
                let species = roll(7)
                let fromLeft = roll(2) == 0
                animals.append(HuntAnimal(id: nextID, species: species, x: fromLeft ? 0 : 500, y: Double(30 + roll(165)), speed: Double(25 + roll(45)) * (fromLeft ? 1 : -1)))
                nextID += 1
            }
        }
    }

    @discardableResult mutating func shoot(x: Double, y: Double) -> Bool {
        guard !finished, x.isFinite, y.isFinite else { return false }
        shots += 1
        if let index = animals.lastIndex(where: { !$0.hit && hypot($0.x - x, $0.y - y) <= $0.radius }) {
            animals[index].hit = true
            food += animals[index].weight
            return true
        }
        return false
    }

    private mutating func roll(_ upper: Int) -> Int {
        randomState = UInt32((UInt64(randomState) * 1_103_515_245 + 12_345) & 0x7fff_ffff)
        return Int((UInt64(randomState) * UInt64(upper)) >> 31)
    }
}

struct RaftObstacle: Identifiable {
    let id: Int
    let x: Double
    var distance: Double
    var passed = false
}

struct RaftSession {
    private(set) var position = 0.5
    private(set) var elapsed = 0.0
    private(set) var collisions = 0
    private(set) var obstacles: [RaftObstacle] = []
    private var spawnClock = 0.0
    private var nextID = 0
    private var randomState: UInt32
    let duration = 60.0
    var finished: Bool { elapsed >= duration || collisions >= 10 }
    var landed: Bool { elapsed >= duration && collisions < 10 }
    var progress: Double { min(1, elapsed / duration) }

    init(seed: UInt32) { randomState = seed }

    mutating func steer(to x: Double) { if x.isFinite && !finished { position = min(0.92, max(0.08, x)) } }

    mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0, !finished else { return }
        var left = min(seconds, duration - elapsed)
        while left > 0 && !finished {
            let dt = min(left, 0.02)
            elapsed += dt; left -= dt; spawnClock += dt
            for i in obstacles.indices {
                let before = obstacles[i].distance
                obstacles[i].distance -= dt * 0.3
                if !obstacles[i].passed && before > 0.15 && obstacles[i].distance <= 0.15 {
                    obstacles[i].passed = true
                    if abs(obstacles[i].x - position) < 0.09 { collisions += 1 }
                }
            }
            obstacles.removeAll { $0.distance < -0.1 }
            if spawnClock >= 1.2 && elapsed < duration - 3 {
                spawnClock = 0
                randomState = UInt32((UInt64(randomState) * 1_103_515_245 + 12_345) & 0x7fff_ffff)
                let x = 0.13 + Double(randomState) / Double(0x7fff_ffff) * 0.74
                obstacles.append(RaftObstacle(id: nextID, x: x, distance: 1.1))
                nextID += 1
            }
        }
    }
}
