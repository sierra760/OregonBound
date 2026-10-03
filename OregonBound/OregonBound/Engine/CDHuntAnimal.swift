/// CD CODE14:1f7c animal callback followed by CODE6:0072 animation and movement.
/// Keeps logical position, collision bounds and bitmap bounds separate, including
/// the original full-size collision bounds during a depth sprite's first frame.
struct CDHuntAnimal: Equatable {
    typealias Rect = OriginalHuntSession.Rect
    struct StopTimers: Equatable {
        var movingPoseDeadline = 0
        var stillPoseDeadline = 0
    }
    struct Profile: Equatable {
        let speed: Int, period: Int, lastFrame: Int, deathFrames: Int, behaviorFrames: Int
        let foodBase: Int, foodSpan: Int
        var liveLast: Int { lastFrame - deathFrames - behaviorFrames }
        var deathLast: Int { lastFrame - behaviorFrames }
        var deathFirst: Int { deathLast - deathFrames + 1 }
    }
    static let profiles: [Profile] = {
        let speed = [3,8,9,7,6,4,10,8,8,8,5]
        let period = [3,2,2,2,2,2,2,2,2,2,2]
        let last = [8,8,4,4,8,9,7,11,5,11,5]
        let death = [2,2,2,2,2,2,2,2,2,2,0]
        let behavior = [3,4,0,0,4,0,3,0,0,0,0]
        let base = [250,35,1,1,175,90,20,2,1,1,0]
        let span = [270,25,2,1,180,30,10,3,1,1,0]
        return (0..<11).map { Profile(speed: speed[$0],period: period[$0],lastFrame: last[$0],
                                     deathFrames: death[$0],behaviorFrames: behavior[$0],foodBase: base[$0],foodSpan: span[$0]) }
    }()
    let id: Int
    let species: Int
    let depth: Int
    let frames: [Rect]
    private(set) var x: Int, y: Int
    private(set) var rect: Rect
    private(set) var velocityX: Int
    private(set) var velocityY = 0
    private(set) var frame = 0
    private(set) var firstFrame = 0
    private(set) var lastFrame: Int
    private(set) var framePeriod: Int
    private(set) var framePhase = 0
    private(set) var behavior = 0
    private(set) var dead = false
    private(set) var deleted = false
    private(set) var mirrored: Bool
    private var savedVelocityOrFallThreshold = 0
    private var movementEnabled = true
    private var sourceBounds: Rect
    var profile: Profile { Self.profiles[species] }
    var category: Int { species + (dead ? 3 : -11) }
    var resource: Int { 19161 + species + [0,200,300][depth] }
    /// Source/destination translations have scale one. Clip to the selected
    /// bitmap's bounds instead of stretching depth art to the collision bounds.
    var drawRect: Rect {
        let bitmap = frames[frame]
        let left = max(sourceBounds.x,bitmap.x), top = max(sourceBounds.y,bitmap.y)
        return Rect(x: x+left,y: y+top,width: max(0,min(sourceBounds.right,bitmap.right)-left),
                    height: max(0,min(sourceBounds.bottom,bitmap.bottom)-top))
    }

    init(id: Int, species: Int, depth: Int, x: Int, y: Int, fromLeft: Bool,
         initialBounds: Rect, frames: [Rect]) {
        precondition((0..<11).contains(species) && (0...2).contains(depth))
        precondition(frames.count > Self.profiles[species].lastFrame)
        self.id = id; self.species = species; self.depth = depth
        self.x = x; self.y = y; self.frames = frames
        sourceBounds = initialBounds
        rect = Rect(x: x+initialBounds.x,y: y+initialBounds.y,width: initialBounds.width,height: initialBounds.height)
        velocityX = Self.profiles[species].speed * (fromLeft ? 1 : -1)
        mirrored = !fromLeft
        lastFrame = Self.profiles[species].liveLast
        framePeriod = Self.profiles[species].period
    }

    mutating func hit(atY y: Int) {
        guard !dead, species != 10 else { return }
        dead = true
        savedVelocityOrFallThreshold = max(229-y,y)
    }

    /// Returns the signed change to the original live counter. In particular,
    /// falling birds decrement it on every falling callback, not just on death.
    @discardableResult mutating func advance(tick: Int, startled: Bool,
        obstacles: [TerrainExtractor.Obstacle], clear: Bool = false,
        timers: inout StopTimers, random: (Int)->Int) -> Int {
        if deleted || clear { deleted = true; return -1 }
        var liveDelta = 0
        if dead {
            if behavior != -1 || (species > 6 && velocityX != 0) {
                behavior = -1
                framePeriod = profile.period
                setCycle(first: profile.deathFirst,last: profile.deathLast)
                if species > 6 && y < savedVelocityOrFallThreshold {
                    velocityY = min(10,velocityY+1)
                    movementEnabled = true
                } else {
                    velocityX = 0; velocityY = 0; movementEnabled = false
                }
                liveDelta -= 1
            } else if frame == lastFrame { framePeriod = 0 }
        } else {
            if (velocityX < 0 && x <= 9-rect.width) || (velocityX >= 0 && x >= 503) {
                deleted = true; liveDelta -= 1
            }
            if startled {
                if canStop && (behavior == 1 || behavior == 2) { resume() }
            } else if random(100) < 1 && canStop {
                advanceStop(tick: tick,timers: &timers,random: random)
            }
            var turn = random(100) < 2
            let foot = Rect(x: rect.x+velocityX,y: rect.bottom-2,width: rect.width,height: 2)
            let terrainHit = species < 7 && obstacles.contains {
                foot.x < $0.right && foot.right > $0.left && foot.y < $0.bottom && foot.bottom > $0.top
            }
            if terrainHit {
                turn = true
                if random(3) == 0 {
                    turn = false
                    if canStop {
                        let previous = behavior
                        advanceStop(tick: tick,timers: &timers,random: random)
                        if previous == 1 && behavior == 0 { turn = true }
                    }
                }
            }
            if turn && behavior == 0 && rect.x >= 9 && rect.right <= 503 && species < 7 {
                velocityX = -velocityX
                mirrored = velocityX < 0
                setCycle(first: 0,last: profile.liveLast)
            }
        }
        if framePeriod != 0 {
            framePhase += 1
            if framePhase >= framePeriod {
                setFrame(frame == lastFrame ? firstFrame : frame+1)
                framePhase = 0
            }
        }
        if movementEnabled {
            x += velocityX; y += velocityY
            rect.x += velocityX; rect.y += velocityY
        }
        return liveDelta
    }

    private var canStop: Bool { [0,1,4,6].contains(species) }
    private mutating func advanceStop(tick: Int,timers: inout StopTimers,random: (Int)->Int) {
        if behavior == 0 {
            setCycle(first: profile.lastFrame-2,last: profile.lastFrame-1)
            savedVelocityOrFallThreshold = velocityX; velocityX = 0
            framePeriod = 10+random(40)
            behavior = 2; timers.movingPoseDeadline = tick+100
        } else if behavior == 2 {
            guard tick >= timers.movingPoseDeadline else { return }
            setCycle(first: profile.lastFrame,last: profile.lastFrame)
            velocityX = 0; behavior = 1
            timers.stillPoseDeadline = tick+100+random(300)
        } else if tick >= timers.stillPoseDeadline { resume() }
    }
    private mutating func resume() {
        setCycle(first: 0,last: profile.liveLast)
        velocityX = savedVelocityOrFallThreshold
        framePeriod = profile.period; behavior = 0
    }
    private mutating func setCycle(first: Int,last: Int) {
        firstFrame = first; lastFrame = last; setFrame(first)
    }
    private mutating func setFrame(_ value: Int) {
        guard frame != value else { return }
        frame = value; sourceBounds = frames[value]
        rect = Rect(x: x+sourceBounds.x,y: y+sourceBounds.y,width: sourceBounds.width,height: sourceBounds.height)
    }
}
