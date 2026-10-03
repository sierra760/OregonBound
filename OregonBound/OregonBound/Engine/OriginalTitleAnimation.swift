/// Classic title animation (CODE4:0000–0d20) and CD static painting (CODE5:052a–06d2).
/// All coordinates are top-left coordinates in the full 512×322 content window.
/// See docs/ORIGINAL_ANIMATION.md and scripts/analysis_animation.py for evidence.
struct OriginalTitleAnimation: Sendable {
    enum Motion: Equatable, Sendable { case loop, pingpong }

    struct Track: Equatable, Sendable {
        let firstFrame: Int
        let lastFrame: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let pauseBase: Int
        let randomSpan: Int
        /// Engine updates per frame. One engine update occurs after two Mac ticks.
        let period: Int
        let repeats: Int
        let motion: Motion
    }

    struct State: Equatable, Sendable {
        var frame: Int
        var delay: Int
        var repeatsRemaining: Int
        var direction = 1
        var phase = 0
        var rate = 0
    }

    struct DrawCommand: Equatable, Sendable {
        let resourceID: Int
        let frame: Int
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        /// All original Imag 19000 source rectangles start at (0,0).
        var sourceX: Int { 0 }
        var sourceY: Int { 0 }
    }

    static let tickInterval = 2
    static let tracks: [Track] = [
        Track(firstFrame: 1, lastFrame: 9, x: 222, y: 113, width: 46, height: 32, pauseBase: 0, randomSpan: 0, period: 15, repeats: 1, motion: .pingpong),
        Track(firstFrame: 10, lastFrame: 12, x: 79, y: 152, width: 26, height: 14, pauseBase: 40, randomSpan: 30, period: 5, repeats: 3, motion: .loop),
        Track(firstFrame: 13, lastFrame: 15, x: 19, y: 128, width: 30, height: 24, pauseBase: 30, randomSpan: 40, period: 90, repeats: 1, motion: .pingpong),
        Track(firstFrame: 16, lastFrame: 17, x: 141, y: 158, width: 31, height: 26, pauseBase: 80, randomSpan: 80, period: 25, repeats: 1, motion: .loop),
        Track(firstFrame: 18, lastFrame: 19, x: 109, y: 158, width: 30, height: 26, pauseBase: 40, randomSpan: 80, period: 30, repeats: 1, motion: .loop),
        Track(firstFrame: 20, lastFrame: 29, x: 368, y: 161, width: 34, height: 30, pauseBase: 80, randomSpan: 300, period: 1, repeats: 1, motion: .loop),
        Track(firstFrame: 30, lastFrame: 37, x: 438, y: 166, width: 30, height: 28, pauseBase: 100, randomSpan: 300, period: 1, repeats: 1, motion: .loop),
        Track(firstFrame: 38, lastFrame: 40, x: 456, y: 194, width: 24, height: 20, pauseBase: 140, randomSpan: 300, period: 4, repeats: 1, motion: .pingpong),
        Track(firstFrame: 41, lastFrame: 42, x: 296, y: 186, width: 26, height: 12, pauseBase: 160, randomSpan: 300, period: 16, repeats: 1, motion: .pingpong),
        Track(firstFrame: 43, lastFrame: 44, x: 326, y: 275, width: 32, height: 24, pauseBase: 40, randomSpan: 100, period: 1, repeats: 3, motion: .pingpong),
        Track(firstFrame: 45, lastFrame: 46, x: 212, y: 205, width: 44, height: 44, pauseBase: 40, randomSpan: 60, period: 1, repeats: 3, motion: .pingpong),
    ]

    let edition: GameEdition
    let monochrome: Bool
    var resourceID: Int { edition == .macintoshCD12 ? (monochrome ? 9001 : 19001) : 19000 }
    private(set) var states: [State]

    /// Calls the supplied random helper in track creation order.
    /// The helper must return zero when the span is zero.
    init(edition: GameEdition = .macintosh11, monochrome: Bool = false, random: (Int) -> Int) {
        self.edition = edition
        self.monochrome = monochrome
        states = (edition == .macintoshCD12 ? [] : Self.tracks).map {
            State(frame: $0.firstFrame, delay: Self.word(random($0.randomSpan)), repeatsRemaining: $0.repeats)
        }
    }

    /// One original engine update. The renderer owns TickCount scheduling:
    /// after an update, set the next deadline to current ticks+2, with no catch-up.
    mutating func step(random: (Int) -> Int) {
        for index in states.indices {
            let track = Self.tracks[index]
            var state = states[index]
            if state.delay != 0 {
                state.delay = Self.word(state.delay - 1)
            } else {
                state.rate = track.period
                if state.phase == 0 {
                    var next = state.frame + (track.motion == .pingpong ? state.direction : 1)
                    if next > track.lastFrame {
                        next = track.motion == .pingpong ? track.lastFrame - 1 : track.firstFrame
                        if track.motion == .pingpong { state.direction = -1 }
                        state.repeatsRemaining -= 1
                    } else if next < track.firstFrame {
                        next = track.firstFrame + 1
                        state.direction = 1
                    }
                    state.frame = next
                    if next == track.firstFrame && state.repeatsRemaining == 0
                        && (track.motion == .loop || state.direction == -1) {
                        state.delay = Self.word(track.pauseBase + random(track.randomSpan))
                        state.repeatsRemaining = track.repeats
                        state.rate = 0
                    }
                }
            }
            // CODE 5: callback runs before incrementing the animation phase.
            if state.rate != 0 {
                state.phase += 1
                if state.phase >= state.rate { state.phase = 0 }
            }
            states[index] = state
        }
    }

    /// Back-to-front opaque srcCopy draws. The original title uses no masks.
    var drawCommands: [DrawCommand] {
        if edition == .macintoshCD12 {
            // Authored bitmap extends two pixels beyond the 494×304 dialog item.
            // The compositor clips that overflow; it never scales the painting.
            return [DrawCommand(resourceID: resourceID, frame: 0, x: 9, y: 9, width: 496, height: 306)]
        }
        var commands = [DrawCommand(resourceID: 19000, frame: 0, x: 9, y: 9, width: 494, height: 304)]
        for index in Self.tracks.indices.reversed() {
            let track = Self.tracks[index]
            commands.append(DrawCommand(resourceID: 19000, frame: states[index].frame,
                                        x: track.x, y: track.y, width: track.width, height: track.height))
        }
        return commands
    }

    private static func word(_ value: Int) -> Int {
        Int(Int16(truncatingIfNeeded: value))
    }
}
