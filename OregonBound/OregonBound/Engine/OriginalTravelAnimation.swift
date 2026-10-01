/// Verified Imag15100 composition and strip/wagon callbacks from CODE1:0x3a92.
/// Adaptive landmark callback CODE1:42d4 and signed16.16 CODE5 movement helpers.
struct OriginalTravelAnimation: Sendable {
    struct Input: Equatable, Sendable {
        var pace: Int
        var destinationIndex: Int
        var remainingMiles: Int
        var month: Int
        var weather: Int
        var snow: Int
        var lastMovement: Int = 0 // Display world+23d, preserved on nonmoving days.
        var dayDelay: Int = 4 // Active world+243; original default Medium.
        var crossingPending: Bool = false // Active wagon second status byte &2.
    }

    struct Rect: Equatable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    struct DrawCommand: Equatable, Sendable {
        let frame: Int
        let destination: Rect
        var source: Rect { Rect(x: 0, y: 0, width: destination.width, height: destination.height) }

        /// Original unscaled srcCopy clipped to (64,9)..<(326,86).
        var clipped: (source: Rect, destination: Rect)? {
            let left = max(destination.x, 64), top = max(destination.y, 9)
            let right = min(destination.x + destination.width, 326)
            let bottom = min(destination.y + destination.height, 86)
            guard left < right && top < bottom else { return nil }
            let target = Rect(x: left, y: top, width: right - left, height: bottom - top)
            return (Rect(x: left - destination.x, y: top - destination.y,
                         width: target.width, height: target.height), target)
        }
    }

    struct Palette: Equatable, Hashable, Sendable {
        /// Copy this original palette entry to live ground index229.
        let groundSource: Int
        /// Copy this original palette entry to live sky index233.
        let skySource: Int
    }

    static let tickInterval = 3
    static let viewport = Rect(x: 64, y: 9, width: 262, height: 77)
    static let frameSizes: [(width: Int, height: Int)] = [
        (262,77),(786,14),(786,6),(67,25),(67,25),(67,25),(67,25),(67,25),
        (62,32),(61,32),(85,28),(117,25),(112,16),(97,20),(59,31),
        (90,22),(91,23),(89,30),(52,32),(96,31),(46,35),(95,34),
    ]
    private static let sceneCodes = [0,13,13,1,2,3,4,5,6,13,7,8,13,9,10,11,12,14]

    /// Literal callback state, including the original divergent origin/rect.
    struct Landmark: Sendable {
        private let frameSizes: [(width: Int, height: Int)]
        var frame: Int
        var x: Int
        var y: Int
        var left: Int
        var top: Int
        var fixedX: Int32 = 0
        var fixedY: Int32 = 0
        var velocityX: Int32 = 0
        var velocityY: Int32 = 0
        var previousMiles = -1
        var previousX = 0
        var calls = 0
        var totalTicks = 0
        var previousTick = 0
        var averageTicks = 5
        var duration = 0
        var delta = 0
        var width: Int { frameSizes[frame].width }
        var height: Int { frameSizes[frame].height }
        var atArrivalEdge: Bool { x == 254-width }

        init(input: Input, frameSizes: [(width: Int, height: Int)] = OriginalTravelAnimation.frameSizes) {
            self.frameSizes = frameSizes
            frame = OriginalTravelAnimation.frameIndex(for: input.destinationIndex)
            let size = frameSizes[frame]
            x = input.destinationIndex < 0 || input.crossingPending ? -746 : 254-size.width-3*input.remainingMiles
            y = 46+(35-size.height)/2
            left = x; top = y
        }
        mutating func move(duration: Int, dx: Int, dy: Int = 0) {
            // Helper parameters are signed16 words even though callers push longs.
            let ticks = Int32(Int16(truncatingIfNeeded: duration))
            let dx = Int(Int16(truncatingIfNeeded: dx)), dy = Int(Int16(truncatingIfNeeded: dy))
            if ticks != 0 {
                fixedX = Int32(x) << 16; fixedY = Int32(y) << 16
                velocityX = (Int32(dx) << 16)/ticks
                velocityY = (Int32(dy) << 16)/ticks
            } else {
                x += dx; left += dx; y += dy; top += dy
                // CODE5:0a32 does not reset fixed positions or velocities.
            }
        }
        mutating func advance(input: Input, tick: Int, endTick: Int) {
            calls += 1
            if totalTicks == 0 { totalTicks = 5; averageTicks = 5 }
            else {
                totalTicks += min(tick-previousTick,15)
                averageTicks = totalTicks/calls
            }
            previousTick = endTick
            precondition(averageTicks > 0, "Original callback requires advancing TickCount")
            var nextDuration = input.dayDelay*60/averageTicks
            if previousMiles < input.remainingMiles {
                let nextFrame = OriginalTravelAnimation.frameIndex(for: input.destinationIndex)
                if frame != nextFrame { frame = nextFrame; left = x; top = y }
                let newX = 254-(3*input.remainingMiles+width)
                let newY = 46+(35-height)/2
                move(duration: 0, dx: newX-x, dy: newY-y)
                previousX = -999
            }
            if previousMiles != input.remainingMiles {
                let desired = 254-(3*(input.remainingMiles-input.lastMovement/2)+width)
                var distance = desired-x
                if distance <= 0 { distance = 3*(20+10*input.pace) }
                if distance > 175 { nextDuration = 0 }
                distance = min(distance,70)
                previousMiles = input.remainingMiles
                duration = nextDuration; delta = distance
                move(duration: nextDuration, dx: distance)
            }
            fixedX = fixedX &+ velocityX; fixedY = fixedY &+ velocityY
            let nextX = Int((fixedX &+ 0x8000) >> 16)
            let nextY = Int((fixedY &+ 0x8000) >> 16)
            left += nextX-x; top += nextY-y; x = nextX; y = nextY
            if x < previousX { x = previousX+5; left = previousX }
            if x > 254-width { x = 254-width; left = x }
            previousX = x
        }
    }

    private(set) var input: Input
    private(set) var landmark: Landmark
    private(set) var wagonFrame = 3
    private(set) var wagonPhase = 0
    private let upperStripWidth: Int
    private let lowerStripWidth: Int
    private let selectedFrameSizes: [(width: Int, height: Int)]
    private(set) var upperStripX: Int
    private(set) var upperStripPhase = 0
    private(set) var lowerStripX: Int
    private var nominalTick = 0

    init(input: Input, upperStripWidth: Int = 786, lowerStripWidth: Int = 786,
         frameSizes: [(width: Int, height: Int)] = OriginalTravelAnimation.frameSizes) {
        precondition(upperStripWidth >= Self.viewport.width && lowerStripWidth >= Self.viewport.width)
        precondition(frameSizes.count == Self.frameSizes.count && frameSizes.allSatisfy { $0.width > 0 && $0.height > 0 })
        selectedFrameSizes = frameSizes
        self.upperStripWidth = upperStripWidth; self.lowerStripWidth = lowerStripWidth
        upperStripX = 326-upperStripWidth; lowerStripX = 326-lowerStripWidth
        precondition((0...2).contains(input.pace))
        self.input = input
        landmark = Landmark(input: input, frameSizes: frameSizes)
    }
    mutating func apply(_ value: Input) {
        precondition((0...2).contains(value.pace))
        input = value
    }
    /// Deterministic nominal-cadence convenience; production passes TickCount.
    mutating func step() {
        nominalTick += Self.tickInterval
        step(tick: nominalTick)
    }
    mutating func step(tick: Int) { step(readTick: { tick }) }

    /// One engine update, with the original two TickCount reads on later calls.
    mutating func step(readTick: () -> Int) {
        // Engine creation order: wagon sees the pre-callback landmark position.
        if !landmark.atArrivalEdge {
            wagonPhase += 1
            if wagonPhase >= 3-input.pace {
                wagonFrame = wagonFrame == 6 ? 3 : wagonFrame+1
                wagonPhase = 0
            }
        }
        let tick = readTick()
        let endTick = landmark.calls == 0 ? tick : readTick()
        landmark.advance(input: input, tick: tick, endTick: endTick)
        // Strips see the landmark AFTER its callback. Wrapping precedes movement.
        if lowerStripX >= 64 { lowerStripX = 326-lowerStripWidth }
        if !landmark.atArrivalEdge { lowerStripX += input.pace+1 }
        if upperStripX >= 64 { upperStripX = 326-upperStripWidth }
        if !landmark.atArrivalEdge {
            upperStripPhase += 1
            if upperStripPhase >= 3-input.pace {
                upperStripX += 1; upperStripPhase = 0
            }
        }
    }

    var palette: Palette {
        let sky = input.weather <= 1 ? 230 : input.weather <= 3 ? 232 : 231
        let greenMonths: ClosedRange<Int>?
        switch input.destinationIndex {
        case 4: greenMonths = nil
        case ..<5: greenMonths = 4...9
        case 5..<13: greenMonths = 4...5
        case 13: greenMonths = 4...10
        default: greenMonths = 3...10
        }
        let ground = input.snow != 0 ? 227 : (greenMonths?.contains(input.month) == true ? 226 : 228)
        return Palette(groundSource: ground, skySource: sky)
    }

    private static func frameIndex(for destination: Int) -> Int {
        precondition((-1...16).contains(destination))
        let requested = sceneCodes[destination+1]+7
        return requested < 8 ? requested+14 : requested
    }
    var landmarkFrame: Int? { landmark.frame }

    /// Back-to-front draw order, in full original-window coordinates.
    var drawCommands: [DrawCommand] {
        var result = [command(0, 64, 9), command(1, upperStripX, 32), command(2, lowerStripX, 81)]
        if let frame = landmarkFrame {
            result.append(command(frame, landmark.left, landmark.top))
        }
        result.append(command(wagonFrame, 256, 54))
        return result
    }

    private func command(_ frame: Int, _ x: Int, _ y: Int) -> DrawCommand {
        let size = selectedFrameSizes[frame]
        return DrawCommand(frame: frame, destination: Rect(x: x, y: y, width: frame == 1 ? upperStripWidth : frame == 2 ? lowerStripWidth : size.width, height: size.height))
    }
}
