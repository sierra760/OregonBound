import Foundation

/// CODE17, using full 512×322 window coordinates and the original color update rate.
/// Independent of rendering; the result is the copied wagon's actual cumulative losses.
struct OriginalRaftSession {
    struct Input: Equatable, Codable {
        var inventory: [Int]
        var living: [Bool]
        var names: [String]
        var rain: Int
        var pixelDepth = 4
    }
    struct Result: Equatable, Codable {
        let initialInventory: [Int]
        let remainingInventory: [Int]
        let initialLiving: [Bool]
        let drownedMembers: [Int]
        var losses: [Int] { zip(initialInventory, remainingInventory).map { max(0,$0-$1) } }
        var survivors: Int { initialLiving.filter { $0 }.count - drownedMembers.count }
    }
    /// The original110-byte local wagon copy begins before the preparation pane.
    struct JourneyState: Codable, Equatable {
        let input: Input
        var preparedResult: Result?
        var commandQuantities: [Int]?
        var appliedResult: Result?
    }
    struct Collision: Equatable {
        let losses: [Int]
        let drownedMembers: [Int]
    }
    struct Rock: Equatable, Identifiable {
        let id: Int
        let slot: Int
        let lane: Int
        var x: Int
        var y = 39
        var frame = 10
        var accumulator: Float = 0
        var slope: Float { Float(Double(lane) * 0.0178) }
    }
    struct DrawCommand: Equatable, Identifiable {
        let id: Int, resource: Int, frame: Int, x: Int, y: Int, width: Int, height: Int
        var mirrored = false
        var masked = false
    }
    enum Event: Equatable { case collision(Collision), finished(Result) }
    let input: Input
    let edition: GameEdition
    private(set) var inventory: [Int]
    private(set) var living: [Bool]
    private(set) var drownedMembers: [Int] = []
    private(set) var rocks: [Rock] = [] // CODE17:16d8 inserts each before raft, after older rocks.
    private(set) var remaining = 1340
    private(set) var raftLeft = 159
    private(set) var raftSpriteLeft = 159
    private(set) var direction = 0
    private(set) var markerX = 462
    private(set) var markerY = 290
    private(set) var shoreFrame = 0
    private(set) var pauseSteps = 0
    private(set) var collision: Collision?
    private(set) var result: Result?
    private(set) var nextTick: Int
    private(set) var cooldown = 20
    private var shorePhase = 0
    private var previousLane = -999 // CODE21 A5−1982 initializer; reset after first creation too.
    private var nextID = 0
    private var events: [Event] = []
    private var pausedAt: Int?
    var isComplete: Bool { result != nil }
    var maximumRocks: Int { min(3,max(1,4-(input.rain-400)/150)) }

    init(input: Input, startTick: Int, edition: GameEdition = .macintosh11, random: (Int)->Int) {
        precondition(input.inventory.count == Inventory.itemCount(for: edition) && (1...5).contains(input.living.count))
        precondition(input.names.count == input.living.count && input.inventory.allSatisfy { $0 >= 0 })
        self.edition = edition
        self.input = input; inventory = input.inventory; living = input.living; nextTick = startTick
        spawn(random: random)
        previousLane = -999 // CODE17:04ce follows initial creation at0412.
    }
    mutating func takeEvents() -> [Event] { defer { events.removeAll() }; return events }
    mutating func dismissCollision() { if pauseSteps != 0 { pauseSteps = 1 } }
    /// Native lifecycle policy, not an original in-game Pause command.
    mutating func setPaused(_ value: Bool, at tick: Int) {
        if value, pausedAt == nil { pausedAt = tick }
        else if !value, let since = pausedAt { nextTick += max(0,tick-since); pausedAt = nil }
    }
    /// CODE17:04d8–0636. One idle update, no elapsed-time catch-up.
    mutating func advance(to tick: Int, mouseX: Int?, random: (Int)->Int) {
        guard !isComplete, pausedAt == nil else { return }
        // Both redraw transition decrements precede even the deadline test.
        if pauseSteps == 100 || pauseSteps == 1 {
            pauseSteps -= 1
            if pauseSteps == 0 { collision = nil }
        }
        guard tick >= nextTick else { return }
        if pauseSteps != 0 { pauseSteps -= 1; nextTick = tick+2; return }
        direction = mouseX.map { $0 > raftLeft+63 ? 1 : $0 < raftLeft ? -1 : 0 } ?? 0
        if cooldown != 0 { cooldown -= 1 }
        let old = remaining
        remaining = Int(Int16(truncatingIfNeeded: remaining-1))
        if old == 0 || !living.contains(true) { finish(); return }
        if input.pixelDepth > 2 { remaining = Int(Int16(truncatingIfNeeded: remaining-1)) }
        nextTick = tick+3
        let roll = random(40) // Unconditional, including end-of-river and full rock slots.
        if (roll == 7 || rocks.isEmpty) && cooldown == 0 && remaining > 150 && rocks.count < maximumRocks {
            cooldown = 20; spawn(random: random)
        }
        // CODE5:00d4 callback,0114 movement; rocks precede raft in object list.
        var survivors: [Rock] = []
        for var rock in rocks {
            if Self.hits(rockX: rock.x, rockY: rock.y, raftLeft: raftLeft, direction: direction) {
                let loss = resolveCollision(random: random)
                collision = loss; pauseSteps = 100; events.append(.collision(loss))
                continue
            }
            if rock.y > 313 { continue }
            rock.accumulator = Float(Double(rock.accumulator) + Double(rock.slope)*2)
            var dx = 0
            if rock.slope < 0 && rock.accumulator < -2 { dx = -2; rock.accumulator += 2 }
            if rock.slope > 0 && rock.accumulator > 2 { dx = 2; rock.accumulator -= 2 }
            rock.frame = Self.rockFrame(top: rock.y) // Frame selected BEFORE generic movement.
            rock.x += dx; rock.y += 2
            survivors.append(rock)
        }
        rocks = survivors
        var velocity = direction*4
        raftLeft += velocity
        if raftLeft > 350 { raftLeft = 350; velocity = 0; direction = 0 }
        if raftLeft < 10 { raftLeft = 10; velocity = 0; direction = 0 }
        // Original clamp updates the global, clears velocity, but does not reposition object.
        raftSpriteLeft += velocity
        let progress = (1340-remaining)/5
        markerX += Int(Double(Self.markerTarget(progress: progress))-Double(markerX))
        markerY = 290-progress
        shorePhase += 1
        if shorePhase >= 5 { shorePhase = 0; shoreFrame = (shoreFrame+1)%11 }
    }
    private mutating func spawn(random: (Int)->Int) {
        var lane: Int
        repeat {
            lane = 23-7*random(8)
            if previousLane == -999 { previousLane = lane }
        } while abs(lane-previousLane) < 15
        previousLane = lane
        let used = Set(rocks.map(\.slot))
        let slot = (0..<3).first { !used.contains($0) }!
        rocks.append(Rock(id: nextID,slot: slot,lane: lane,x: 189+2*lane)); nextID += 1
    }
    private mutating func resolveCollision(random: (Int)->Int) -> Collision {
        var losses = Array(repeating: 0,count: inventory.count)
        for i in 1..<inventory.count where inventory[i] != 0 {
            if random(100) < 50 { losses[i] = random(inventory[i]+1) }
        }
        for _ in 0..<((inventory[0]+1)/2) { if random(100) < 40 { losses[0] += 2 } }
        losses[0] = min(inventory[0],losses[0])
        var deaths: [Int] = []
        for member in living.indices.dropFirst() where living[member] {
            if random(100) < 40 { living[member] = false; deaths.append(member) }
        }
        if living.filter({ $0 }).count == 1 && living[0] && random(100) < 40 {
            living[0] = false; deaths.append(0)
        }
        for i in inventory.indices { inventory[i] -= losses[i] }
        drownedMembers += deaths
        return Collision(losses: losses,drownedMembers: deaths)
    }
    private mutating func finish() {
        let value = Result(initialInventory: input.inventory,remainingInventory: inventory,
                           initialLiving: input.living,drownedMembers: drownedMembers.sorted())
        result = value; events.append(.finished(value))
    }
    static func rockFrame(top: Int) -> Int { top < 64 ? 10 : max(5,10-(top-39)/12) }
    /// SANE extended intermediates stored as single, then $0016 truncates target-current.
    static func markerTarget(progress p: Int) -> Float {
        let x: Double
        switch p {
        case ..<19: x = 464 + Double(p)*0.166666667
        case ..<46: x = 466
        case ..<115: x = 466 + Double(p-46)*0.144927537
        case ..<154: x = 475 - Double(p-115)*0.333333334
        case ..<192: x = 462 - Double(p-154)*0.105263158
        case ..<221: x = 457 - Double(p-192)*0.379310345
        default: x = 446
        }
        return Float(x)
    }
    static func hits(rockX x: Int, rockY y: Int, raftLeft: Int, direction: Int) -> Bool {
        if y+31 < 210 || y+5 > 254 || raftLeft > x+64 || raftLeft+60 < x+1 { return false }
        let rocks = [(y+5,x+21,y+21,x+49),(y+21,x+1,y+31,x+64)]
        let edges = [[(21,41),(12,40),(8,48),(6,58)],[(16,36),(17,45),(11,50),(5,57)],
                     [(26,46),(23,49),(13,53),(5,57)]][direction+1]
        let bands = [(210,217),(218,222),(222,240),(240,253)]
        for (i,band) in bands.enumerated() {
            for r in rocks where max(band.0,r.0) < min(band.1,r.2) &&
                max(raftLeft+edges[i].0,r.1) < min(raftLeft+edges[i].1,r.3) { return true }
        }
        return false
    }
    /// CODE5 paints the object list in reverse. Map is created last and painted first.
    var drawCommands: [DrawCommand] {
        let artwork = edition == .macintoshCD12 ? 20000 : 19200
        let shore = edition == .macintoshCD12 ? 20001 : 19201
        var commands = [DrawCommand(id: -10,resource: artwork,frame: 0,x: 416,y: 8,width: 88,height: 306),
                        DrawCommand(id: -2,resource: shore,frame: shoreFrame,x: 327,y: 9,width: 87,height: 111),
                        DrawCommand(id: -1,resource: shore,frame: shoreFrame,x: 7,y: 9,width: 87,height: 111,mirrored: true),
                        DrawCommand(id: -4,resource: artwork,frame: 1,x: markerX,y: markerY,width: 11,height: 11),
                        DrawCommand(id: -3,resource: artwork,frame: direction+3,x: raftSpriteLeft,y: 210,width: 63,height: 52,masked: true)]
        let sizes = [(56,32),(53,29),(49,26),(45,24),(42,23),(40,20)]
        commands += rocks.reversed().map {
            let size = sizes[$0.frame-5]
            return DrawCommand(id: $0.id,resource: artwork,frame: $0.frame,x: $0.x,y: $0.y,width: size.0,height: size.1,masked: true)
        }
        return commands
    }
}
