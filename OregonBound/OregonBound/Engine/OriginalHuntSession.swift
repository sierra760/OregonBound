import Foundation

/// Original color hunting mechanics, CODE13. Full-window coordinates; no SwiftUI/SpriteKit dependency.
struct OriginalHuntSession {
    struct Input: Equatable {
        var destination: Int
        var month: Int
        var weatherCategory: Int
        var snow: Bool
        var mileage: Int
        var lastSuccessfulHuntMileage: Int
        var ammunition: Int
        var survivors: Int
        var currentFood: Int
        var foodCapacity: Int
        /// Original world+247, values1...6:20,30,45,60,90,120 seconds.
        var timeSetting: Int
        /// Original A5−2b76: color resource file available and display depth above one bit.
        /// The native color artwork uses true; false retains the original monochrome branch.
        var originalDisplayFlag: Bool
        var edition: GameEdition = .macintosh11
        var rain: Int = 0
    }
    struct Rect: Equatable {
        var x: Int, y: Int, width: Int, height: Int
        var right: Int { x + width }
        var bottom: Int { y + height }
        func contains(x: Int, y: Int) -> Bool { self.x <= x && x < right && self.y <= y && y < bottom }
    }
    struct Palette: Equatable {
        /// Substitute source indices1/2 BEFORE generating CalcCMask or uploading texture pixels.
        let skyIndex: Int
        let groundIndex: Int
        let skyRGB16: [Int]
        let groundRGB16: [Int]
    }
    struct FillCommand: Equatable { let rect: Rect; let rgb16: [Int] }
    enum Role: Equatable { case backdrop, scenery, animal(Int), projectile }
    enum Transfer: Int { case masked = -1, copy = 0, or = 1 }
    struct Object: Equatable, Identifiable {
        let id: Int
        let role: Role
        let resource: Int
        var category: Int
        var frame: Int
        var rect: Rect
        var mirrored = false
        var visible = true
        var velocity = 0
        var firstFrame = 0
        var lastFrame = 0
        var framePeriod = 0
        var framePhase = 0
        var deleted = false
        let transfer: Transfer
    }
    struct DrawCommand: Equatable, Identifiable {
        let id: Int
        let resource: Int
        let frame: Int
        let rect: Rect
        let mirrored: Bool
        let transfer: Transfer
    }
    struct Result: Equatable {
        let foodShot: Int
        let foodCarried: Int
        let shots: Int
        let lastSuccessfulHuntMileage: Int
        let carryLimit: Int
        /// CODE6:0b28–0c28: STR#3022 indexes2/5/6, followed unconditionally by7.
        var message: String {
            let summary: String
            if foodCarried == foodShot {
                summary = "You brought back \(foodCarried) pound(s) of food and used \(shots) bullet(s)."
            } else if foodCarried == carryLimit {
                summary = "You shot \(foodShot) pound(s) of food using \(shots) bullet(s), but were only able to carry \(foodCarried) pound(s) of food back to your wagon."
            } else {
                summary = "You shot \(foodShot) pound(s) of food using \(shots) bullet(s), but were only able to fit \(foodCarried) more pound(s) of food in your wagon."
            }
            return summary + "  If you continue to hunt in this area, game will become scarce."
        }
    }
    enum Event: Equatable { case fired, dryFire, hit(species: Int, food: Int), blocked, missed, finished(Result) }
    enum ShotResponse: Equatable { case fired, inFlight, noAmmunition, inactive }
    struct Projectile: Equatable {
        var remaining: Int
        var fixedX: Int32, fixedY: Int32
        var dx: Int32, dy: Int32
    }
    static let tickInterval = 3
    // DITL9160 item3 in pane13; CODE13:0ce2 copies the actual item rectangle.
    static let viewport = Rect(x: 9,y: 9,width: 494,height: 262)
    static let seconds = [0,20,30,45,60,90,120]
    static let speed = [3,8,9,7,6,4,10]
    static let period = [3,2,2,2,2,2,2]
    static let lastFrame = [5,4,3,3,4,5,4]
    static let deathCount = [2,2,1,1,2,2,2]
    static let foodBase = [250,35,1,1,175,90,20]
    static let foodSpan = [270,25,2,1,180,30,10]
    static let animalSizes = [(58,38),(61,51),(37,23),(39,19),(58,50),(52,26),(52,43)]
    static let scenerySizes = [(494,25),(494,25),(494,46),(5,5),(63,30),(66,28),(91,33),
                              (85,82),(67,103),(50,91),(55,91),(47,54),(63,30),(66,28),
                              (91,33),(83,82),(53,62),(50,91),(55,91),(47,54)]
    let input: Input
    let palette: Palette
    private(set) var objects: [Object] = [] // Original update/hit order; draw in reverse.
    private(set) var population: [Int]
    private(set) var shots = 0
    private(set) var foodShot = 0
    private(set) var sceneKills = 0
    private(set) var liveAnimals = 0
    private(set) var projectile: Projectile?
    private(set) var result: Result?
    private(set) var endTick: Int
    private(set) var nextTick: Int
    private var pausedAt: Int?
    private var stopping = false
    private var moving = false
    private var sceneStarted = false
    private var nextID = 2
    private var events: [Event] = []
    var isComplete: Bool { result != nil }
    var isPaused: Bool { pausedAt != nil }
    var ammoLimit: Int { min(20,max(0,input.ammunition)) }
    var ammunitionRemaining: Int { max(0,ammoLimit-shots) }
    var repeatedArea: Bool { input.mileage == input.lastSuccessfulHuntMileage }

    init(input: Input, startTick: Int, deferInitialScenery: Bool = false, random: (Int) -> Int) {
        precondition((1...6).contains(input.timeSetting) && (1...12).contains(input.month))
        self.input = input
        palette = Self.palette(destination: input.destination, month: input.month,
                               weather: input.weatherCategory, snow: input.snow)
        endTick = startTick + Self.seconds[input.timeSetting]*60
        nextTick = startTick
        population = Self.initialWeights(destination: input.destination, month: input.month,
                                         repeated: input.mileage == input.lastSuccessfulHuntMileage)
        if input.mileage != input.lastSuccessfulHuntMileage { population[random(2)+2] = 0 }
        while population.filter({ $0 != 0 }).count > 2 { population[random(7)] = 0 }
        objects = [Self.backdrop(id: 0,frame: input.destination < 5 ? 0 : 1,y: 34),
                   Self.backdrop(id: 1,frame: 2,y: 225)]
        if !deferInitialScenery { beginScene(random: random) }
    }

    /// Population selection occurs before DITL9161; scenery creation follows its30-tick timer.
    mutating func beginScene(random: (Int)->Int) {
        guard !sceneStarted else { return }
        sceneStarted = true
        makeScenery(random: random)
    }

    /// Paint before frame commands. CODE13:11f6–124e; foreground overlaps the final9 ground rows.
    var fillCommands: [FillCommand] {
        [FillCommand(rect: Rect(x: Self.viewport.x,y: Self.viewport.y,width: Self.viewport.width,
                               height: 34-Self.viewport.y),rgb16: palette.skyRGB16),
         FillCommand(rect: Rect(x: 9,y: 59,width: 494,height: 175),rgb16: palette.groundRGB16)]
    }
    var drawCommands: [DrawCommand] {
        objects.reversed().compactMap { object in
            guard object.visible && !object.deleted else { return nil }
            return DrawCommand(id: object.id,resource: object.resource,frame: object.frame,
                               rect: object.rect,mirrored: object.mirrored,transfer: object.transfer)
        }
    }
    mutating func takeEvents() -> [Event] { defer { events.removeAll() }; return events }
    func remainingTicks(at tick: Int) -> Int { max(0,endTick-(pausedAt ?? tick)) }

    /// App lifecycle policy: freeze this native session while hidden; original in-game UI has no Pause button.
    mutating func setPaused(_ paused: Bool, at tick: Int) {
        if paused, pausedAt == nil { pausedAt = tick }
        else if !paused, let since = pausedAt {
            endTick += max(0,tick-since); nextTick = tick; pausedAt = nil
        }
    }
    mutating func move() { if !isComplete && !isPaused { moving = true } }
    mutating func stop() { if !isComplete { stopping = true } }

    @discardableResult mutating func shoot(x: Int, y: Int) -> ShotResponse {
        guard !isComplete, !isPaused, !stopping else { return .inactive }
        guard projectile == nil else { return .inFlight }
        guard shots < ammoLimit else { events.append(.dryFire); return .noAmmunition }
        shots += 1
        let count = max(abs(x-256),abs(y-228))/20
        let startX = count == 0 ? x : 256, startY = count == 0 ? y : 228
        projectile = Projectile(remaining: count,fixedX: Int32(startX)<<16,fixedY: Int32(startY)<<16,
                                dx: count == 0 ? 0 : (Int32(x-256)<<16)/Int32(count),
                                dy: count == 0 ? 0 : (Int32(y-228)<<16)/Int32(count))
        let object = Object(id: nextID,role: .projectile,resource: 19160,category: 0,frame: 3,
                            rect: Rect(x: startX,y: startY,width: 5,height: 5),transfer: .or)
        nextID += 1
        objects.insert(object,at: min(1,objects.count)) // CODE13:16ca–16de.
        events.append(.fired)
        return .fired
    }

    /// At most one original idle update. Missed deadlines are never caught up.
    mutating func advance(to tick: Int, random: (Int) -> Int) {
        guard !isComplete, !isPaused, tick >= nextTick else { return }
        if stopping { finish(); return }
        nextTick = tick + Self.tickInterval
        if tick > endTick && projectile == nil { stopping = true }
        let roll = random(repeatedArea ? 150 : 50)
        if roll == 7 && tick+180 < endTick && liveAnimals < 2 && sceneKills < 4 { spawn(random: random) }
        updateObjects(clear: moving,random: random)
        if moving {
            moving = false
            makeScenery(random: random)
            updateObjects(clear: false,random: random) // Original Move path updates the fresh scene too.
        }
    }

    private mutating func updateObjects(clear: Bool, random: (Int) -> Int) {
        for index in objects.indices {
            var object = objects[index]
            switch object.role {
            case .backdrop: break
            case .scenery:
                object.visible = true
                if clear { object.deleted = true }
            case .projectile:
                if clear { projectile = nil; object.deleted = true }
                else if var shot = projectile {
                    if shot.remaining > 0 {
                        shot.fixedX = shot.fixedX &+ shot.dx; shot.fixedY = shot.fixedY &+ shot.dy
                        object.rect.x = Int((shot.fixedX &+ 0x8000)>>16)
                        object.rect.y = Int((shot.fixedY &+ 0x8000)>>16)
                        shot.remaining -= 1; projectile = shot
                    } else {
                        projectile = nil; object.deleted = true
                        resolveImpact(x: object.rect.x,y: object.rect.y,random: random)
                    }
                }
            case .animal(let species):
                if clear { object.deleted = true; liveAnimals -= 1 }
                else if object.category >= 3 {
                    if object.velocity != 0 {
                        object.firstFrame = Self.lastFrame[species]-Self.deathCount[species]+1
                        object.lastFrame = Self.lastFrame[species]
                        object.frame = object.firstFrame
                        object.velocity = 0; liveAnimals -= 1
                    } else if object.frame == object.lastFrame { object.framePeriod = 0 }
                } else {
                    if (object.velocity < 0 && object.rect.x <= 9-object.rect.width) ||
                        (object.velocity >= 0 && object.rect.x >= 503) {
                        object.deleted = true; liveAnimals -= 1
                    }
                    let turn = random(100)
                    if turn < 2 && object.rect.x >= 9 && object.rect.right <= 503 {
                        object.velocity = -object.velocity
                        object.mirrored = object.velocity < 0
                        object.frame = 0 // Frame phase deliberately survives direction changes.
                    }
                }
                if object.framePeriod != 0 {
                    object.framePhase += 1
                    if object.framePhase >= object.framePeriod {
                        object.frame = object.frame == object.lastFrame ? object.firstFrame : object.frame+1
                        object.framePhase = 0
                    }
                }
                object.rect.x += object.velocity
            }
            objects[index] = object
        }
        objects.removeAll(where: \.deleted)
    }

    private mutating func resolveImpact(x: Int,y: Int,random: (Int)->Int) {
        for index in objects.indices {
            let object = objects[index]
            guard (object.category < 0 || object.category == 2),object.rect.contains(x: x,y: y) else { continue }
            guard object.category < 0 else { events.append(.blocked); return }
            let species = object.category+8
            if species != 2 && species != 3 {
                population[species] -= population[species]/2
                if !repeatedArea && population[species] == 1 { population[species] = 0 }
            }
            let food = Self.foodBase[species] + random(Self.foodSpan[species])
            foodShot += food; sceneKills += 1
            objects[index].category += 11
            events.append(.hit(species: species,food: food))
            return
        }
        events.append(.missed)
    }

    private mutating func spawn(random: (Int)->Int) {
        let total = population.reduce(0,+)
        guard total > 0 else { return }
        var value = random(total)
        var selected: Int?
        for species in (0..<7).reversed() {
            if population[species] > value { selected = species; break }
            value -= population[species]
        }
        guard let species = selected else { return }
        let left = random(2) != 0
        let size = Self.animalSizes[species]
        let rect = Rect(x: left ? 9-size.0 : 503,y: 59+random(166-size.1),width: size.0,height: size.1)
        let object = Object(id: nextID,role: .animal(species),resource: 19161+species,
                            category: species-8,frame: 0,rect: rect,mirrored: !left,
                            velocity: Self.speed[species]*(left ? 1 : -1),lastFrame: Self.lastFrame[species]-Self.deathCount[species],
                            framePeriod: Self.period[species],transfer: .masked)
        nextID += 1; liveAnimals += 1
        insertByDepth(object)
    }

    private mutating func insertByDepth(_ object: Object) {
        let depth = object.rect.bottom-(object.category == 2 ? 5 : 0)
        let at = objects.firstIndex { $0.category != 0 && $0.rect.bottom < depth } ?? objects.count
        objects.insert(object,at: at)
    }

    private mutating func makeScenery(random: (Int)->Int) {
        sceneKills = 0; liveAnimals = 0
        let d = input.destination
        let treesAllowed = d != 4
        let forest = d > 4
        let omitFirst = d <= 4 ? d < 2 : (d == 5 || (d > 6 && d < 11) || d > 13)
        let winterPlains = d <= 4 && !(4...9).contains(input.month)
        let countBound = input.originalDisplayFlag ? 1 : 3
        if !omitFirst {
            let count = random(countBound)+(treesAllowed ? 1 : 4)
            for _ in 0..<count { addScenery(base: input.snow ? 12 : 4,count: 2,random: random) }
        }
        let count = random(countBound)+(omitFirst ? 3 : 1)
        let offset = input.snow || (!forest && winterPlains) ? 8 : 0
        if treesAllowed {
            for _ in 0..<count { addScenery(base: (forest ? 9 : 7)+offset,count: forest ? 3 : 1,random: random) }
        }
    }

    private mutating func addScenery(base: Int,count: Int,random: (Int)->Int) {
        let frame = base+random(count)
        let size = Self.scenerySizes[frame]
        let object = Object(id: nextID,role: .scenery,resource: 19160,category: 2,frame: frame,
                            rect: Rect(x: 9+random(494-size.0),y: 59+random(166-size.1),width: size.0,height: size.1),
                            visible: false,transfer: .masked)
        nextID += 1; insertByDepth(object)
    }

    private mutating func finish() {
        let value = Self.settle(foodShot: foodShot, shots: shots, input: input)
        result = value; events.append(.finished(value))
    }

    static func settle(foodShot: Int, shots: Int, input: Input) -> Result {
        let carryLimit = input.survivors > 1 ? 200 : 100
        let carried = min(foodShot,carryLimit,max(0,input.foodCapacity-input.currentFood))
        // CODE13:04c0 updates the mileage BEFORE applying wagon capacity at04fa.
        return Result(foodShot: foodShot,foodCarried: carried,shots: shots,
                      lastSuccessfulHuntMileage: foodShot == 0 ? input.lastSuccessfulHuntMileage : input.mileage,
                      carryLimit: carryLimit)
    }

    private static func backdrop(id: Int,frame: Int,y: Int) -> Object {
        let size = scenerySizes[frame]
        return Object(id: id,role: .backdrop,resource: 19160,category: 0,frame: frame,
                      rect: Rect(x: 9,y: y,width: size.0,height: size.1),transfer: .copy)
    }

    static func initialWeights(destination d: Int,month: Int,repeated: Bool) -> [Int] {
        var weights = [d < 7 ? 15 : 8,(10...14).contains(d) ? 10 : 25,repeated ? 20 : 40,repeated ? 20 : 40,0,0,0]
        if d > 2 && d < 13 { weights[6] = d == 3 || d == 12 ? 7 : 20 }
        if d == 4 || (d > 10 && d < 14) { weights[4] = 8 }
        else if d > 4 { weights[4] = 15 }
        if month > 3 && month < 11 { weights[5] = d > 12 ? 10 : d > 5 ? 5 : 0 }
        return weights
    }

    static func palette(destination d: Int,month: Int,weather: Int,snow: Bool) -> Palette {
        let months: ClosedRange<Int>? = d == 4 ? nil : d < 5 ? 4...9 : d < 13 ? 4...5 : d == 13 ? 4...10 : 3...10
        let green = months?.contains(month) == true
        return Palette(skyIndex: weather > 1 ? 196 : 182,groundIndex: snow ? 0 : green ? 166 : 86,
                       skyRGB16: weather > 1 ? [45220,45220,45220] : [9728,51456,65280],
                       groundRGB16: snow ? [65535,65535,65535] : green ? [0,51456,6912] : [65280,63085,35223])
    }
}
