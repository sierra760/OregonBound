/// Macintosh CD CODE14 hunt. Uses captured source geometry, three authored
/// terrain views, ten huntable species, and the original shared RNG supplied by
/// the caller. Population preparation/reseeding precedes construction.
struct CDHuntSession {
    typealias Input = OriginalHuntSession.Input
    typealias Rect = OriginalHuntSession.Rect
    typealias Result = OriginalHuntSession.Result
    typealias Event = OriginalHuntSession.Event
    typealias ShotResponse = OriginalHuntSession.ShotResponse
    typealias DrawCommand = OriginalHuntSession.DrawCommand
    private enum Object {
        case animal(CDHuntAnimal)
        case scenery(id: Int, frame: Int, rect: Rect)
        case projectile(id: Int, rect: Rect)
        var rect: Rect {
            switch self { case .animal(let a): return a.rect
            case .scenery(_,_,let r), .projectile(_,let r): return r }
        }
        var category: Int {
            switch self { case .animal(let a): return a.category; case .scenery: return 2; case .projectile: return 0 }
        }
    }
    let input: Input
    let assets: CDHuntAssets
    let habitat: Int
    let palette: OriginalHuntSession.Palette
    private var objects: [Object] = []
    private(set) var population: [Int]
    private(set) var view = 0
    private(set) var shots = 0
    private(set) var foodShot = 0
    private(set) var sceneKills = 0
    private(set) var liveAnimals = 0
    private(set) var projectile: OriginalHuntSession.Projectile?
    private(set) var result: Result?
    private(set) var endTick: Int
    private(set) var nextTick: Int
    private(set) var startledUntil: Int?
    private var timers = CDHuntAnimal.StopTimers()
    private var pausedAt: Int?
    private var stopping = false
    private var moving = false
    private var sceneStarted = false
    private var nextID = 1
    private var events: [Event] = []
    var isComplete: Bool { result != nil }
    var isPaused: Bool { pausedAt != nil }
    var ammoLimit: Int { min(20,max(0,input.ammunition)) }
    var ammunitionRemaining: Int { max(0,ammoLimit-shots) }
    var repeatedArea: Bool { input.mileage == input.lastSuccessfulHuntMileage }
    var terrain: TerrainExtractor.Terrain { assets.terrains[19200+10*habitat+view]! }
    var backgroundResource: Int { assets.resource(19200+10*habitat+view+(input.snow ? 3 : 0)) }
    var animals: [CDHuntAnimal] { objects.compactMap { if case .animal(let a) = $0 { return a }; return nil } }

    init(input: Input, preparation: CDHuntRules.Preparation, assets: CDHuntAssets,
         startTick: Int, deferInitialScenery: Bool = false, random: (Int)->Int) {
        precondition((1...6).contains(input.timeSetting) && (1...12).contains(input.month))
        precondition((0..<10).contains(preparation.habitat) && preparation.population.count == 11)
        self.input = input; self.assets = assets; habitat = preparation.habitat
        population = preparation.population
        palette = OriginalHuntSession.palette(destination: input.destination,month: input.month,
                                               weather: input.weatherCategory,snow: input.snow)
        endTick = startTick+OriginalHuntSession.seconds[input.timeSetting]*60
        nextTick = startTick
        if !deferInitialScenery { beginScene(random: random) }
    }
    mutating func beginScene(random: (Int)->Int) {
        guard !sceneStarted else { return }
        sceneStarted = true; makeScenery(random: random)
    }
    var drawCommands: [DrawCommand] {
        let bounds = assets.bounds(19200+10*habitat+view+(input.snow ? 3 : 0))
        let background = DrawCommand(id: 0,resource: backgroundResource,frame: 0,
            rect: Rect(x: 9+bounds.x,y: 9+bounds.y,width: bounds.width,height: bounds.height),mirrored: false,transfer: .copy)
        return [background] + objects.reversed().map { object in
            switch object {
            case .animal(let a):
                return DrawCommand(id: a.id,resource: assets.resource(a.resource),frame: a.frame,
                                   rect: a.drawRect,mirrored: a.mirrored,transfer: .masked)
            case .scenery(let id,let frame,let rect):
                return DrawCommand(id: id,resource: assets.resource(19160),frame: frame,rect: rect,mirrored: false,transfer: .masked)
            case .projectile(let id,let rect):
                return DrawCommand(id: id,resource: assets.resource(19160),frame: 3,rect: rect,mirrored: false,transfer: .or)
            }
        }
    }
    mutating func takeEvents() -> [Event] { defer { events.removeAll() }; return events }
    func remainingTicks(at tick: Int) -> Int { max(0,endTick-(pausedAt ?? tick)) }
    mutating func setPaused(_ paused: Bool,at tick: Int) {
        if paused, pausedAt == nil { pausedAt = tick }
        else if !paused, let since = pausedAt {
            let duration = max(0,tick-since)
            endTick += duration; nextTick = tick
            timers.movingPoseDeadline += duration; timers.stillPoseDeadline += duration
            if let until = startledUntil { startledUntil = until+duration }
            pausedAt = nil
        }
    }
    mutating func move() { if !isComplete && !isPaused { moving = true } }
    mutating func stop() { if !isComplete { stopping = true } }

    @discardableResult mutating func shoot(x: Int,y: Int,at tick: Int) -> ShotResponse {
        guard !isComplete, !isPaused, !stopping else { return .inactive }
        // Caller event sets this even when the fire routine rejects the shot.
        startledUntil = tick+300
        guard projectile == nil else { return .inFlight }
        guard shots < ammoLimit else { events.append(.dryFire); return .noAmmunition }
        shots += 1
        let count = max(abs(x-256),abs(y-228))/20
        let startX = count == 0 ? x : 256, startY = count == 0 ? y : 228
        projectile = .init(remaining: count,fixedX: Int32(startX)<<16,fixedY: Int32(startY)<<16,
                           dx: count == 0 ? 0 : (Int32(x-256)<<16)/Int32(count),
                           dy: count == 0 ? 0 : (Int32(y-228)<<16)/Int32(count))
        let bounds = assets.bounds(19160,3)
        objects.insert(.projectile(id: nextID,rect: Rect(x: startX+bounds.x,y: startY+bounds.y,
            width: bounds.width,height: bounds.height)),at: min(1,objects.count))
        nextID += 1; events.append(.fired); return .fired
    }
    mutating func advance(to tick: Int,random: (Int)->Int) {
        guard !isComplete, !isPaused, tick >= nextTick else { return }
        if stopping { finish(); return }
        nextTick = tick+3
        if let until = startledUntil, nextTick >= until { startledUntil = nil }
        if tick > endTick && projectile == nil { stopping = true }
        let roll = random(repeatedArea ? 150 : 50)
        if roll == 7 && tick+180 < endTick && liveAnimals < 5 && sceneKills < 4 { spawn(random: random) }
        updateObjects(at: tick,clear: moving,random: random)
        if moving {
            moving = false; view = (view+1)%3
            makeScenery(random: random)
            updateObjects(at: tick,clear: false,random: random)
        }
    }
    private mutating func spawn(random: (Int)->Int) {
        var value = random(population.reduce(0,+))
        var selected: Int?
        for species in (0..<11).reversed() {
            if population[species] > value { selected = species; break }
            value -= population[species]
        }
        guard let species = selected else { return }
        var left = random(2) != 0
        if left && !terrain.leftEntryAllowed { left = false }
        if !left && !terrain.rightEntryAllowed { left = true }
        let bounds = assets.bounds(19161+species)
        let x = left ? 9-bounds.width : 503
        var y = 114+random(111-bounds.height)
        var depth: Int
        if (7...9).contains(species) {
            y = 14+random(101); depth = y < 41 ? 0 : y < 77 ? 1 : 2
        } else { depth = y < 130 ? 2 : y < 165 ? 1 : 0 }
        // Class10 is not selected by the recovered population initializer.
        if species == 10 { depth = 0 }
        let resource = 19161+species+[0,200,300][depth]
        let animal = CDHuntAnimal(id: nextID,species: species,depth: depth,x: x,y: y,fromLeft: left,
                                  initialBounds: bounds,frames: assets.frames[resource]!)
        nextID += 1
        liveAnimals = Int(Int16(truncatingIfNeeded: liveAnimals+1))
        let at = objects.firstIndex { $0.category != 0 && $0.rect.bottom < animal.rect.bottom } ?? objects.count
        objects.insert(.animal(animal),at: at)
    }
    private mutating func updateObjects(at tick: Int,clear: Bool,random: (Int)->Int) {
        var removed = Set<Int>()
        for index in objects.indices {
            switch objects[index] {
            case .animal(var animal):
                let delta = animal.advance(tick: tick,startled: startledUntil != nil,obstacles: terrain.obstacles,
                                           clear: clear,timers: &timers,random: random)
                liveAnimals = Int(Int16(truncatingIfNeeded: liveAnimals+delta))
                objects[index] = .animal(animal)
                if animal.deleted { removed.insert(index) }
            case .scenery:
                if clear { removed.insert(index) }
            case .projectile(let id,var rect):
                if clear { projectile = nil; removed.insert(index) }
                else if var shot = projectile {
                    if shot.remaining > 0 {
                        shot.fixedX = shot.fixedX &+ shot.dx; shot.fixedY = shot.fixedY &+ shot.dy
                        rect.x = Int((shot.fixedX &+ 0x8000)>>16); rect.y = Int((shot.fixedY &+ 0x8000)>>16)
                        shot.remaining -= 1; projectile = shot
                        objects[index] = .projectile(id: id,rect: rect)
                    } else {
                        projectile = nil; removed.insert(index)
                        resolveImpact(x: rect.x,y: rect.y,random: random)
                    }
                }
            }
        }
        objects = objects.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
    }
    private mutating func resolveImpact(x: Int,y: Int,random: (Int)->Int) {
        for index in objects.indices {
            let object = objects[index]
            guard (object.category < 0 || object.category == 2), object.rect.contains(x: x,y: y) else { continue }
            guard case .animal(var animal) = object else { events.append(.blocked); return }
            let species = animal.species
            if species == 10 { continue }
            if species != 2 && species != 3 {
                population[species] -= population[species]/2
                if !repeatedArea && population[species] == 1 { population[species] = 0 }
            }
            let profile = animal.profile
            let food = profile.foodBase+random(profile.foodSpan)
            foodShot += food; sceneKills += 1
            animal.hit(atY: y); objects[index] = .animal(animal)
            events.append(.hit(species: species,food: food)); return
        }
        events.append(.missed)
    }
    private mutating func makeScenery(random: (Int)->Int) {
        sceneKills = 0; liveAnimals = 0
        let frame = 4+random(2), bounds = assets.bounds(19160,frame)
        // CODE14:29b0 consumes both coordinates but places this object offscreen.
        _ = random(494-bounds.width); _ = random(111-bounds.height)
        objects.append(.scenery(id: nextID,frame: frame,
            rect: Rect(x: -30+bounds.x,y: -30+bounds.y,width: bounds.width,height: bounds.height)))
        nextID += 1
    }
    private mutating func finish() {
        let settled = Self.settle(foodShot: foodShot,shots: shots,input: input)
        result = settled; events.append(.finished(settled))
    }
    static func settle(foodShot: Int,shots: Int,input: Input) -> Result {
        let carryLimit = input.survivors > 1 ? 250 : 125
        return Result(foodShot: foodShot,foodCarried: min(foodShot,carryLimit,max(0,input.foodCapacity-input.currentFood)),
                      shots: shots,lastSuccessfulHuntMileage: foodShot == 0 ? input.lastSuccessfulHuntMileage : input.mileage,
                      carryLimit: carryLimit)
    }
}
