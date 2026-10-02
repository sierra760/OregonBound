import Foundation

/// CODE7:141e–155c chooses a separate image for each CD landmark and season.
/// CODE4:2908–2952 recreates an existing pane when Conditions draws a changed
/// weather category. Snow accumulation alone does not refresh an open pane.
struct CDLandmarkPresentation {
    struct Artwork: Equatable {
        let monochromeResource: Int
        let colorResource: Int
        // The old scene table supplies a frame, but each CD image has one frame;
        // the source image loader clamps that requested frame to zero.
        let frame = 0
    }
    private(set) var artwork: Artwork?
    private var index: Int?
    private var displayedWeather: Int?
    private var visible = false

    static func artwork(index: Int, weather: Int, snow: Int) -> Artwork? {
        guard (0..<18).contains(index) else { return nil }
        let variant = (weather > 1 ? 1 : 0) + (index != 12 && snow > 0 ? 2 : 0)
        return Artwork(monochromeResource: 5400 + index * 10 + variant,
                       colorResource: 15400 + index * 10 + variant)
    }

    mutating func update(index: Int, weather: Int, snow: Int, displayedWeather: Int, visible: Bool) {
        if visible && (!self.visible || self.index != index || self.displayedWeather != displayedWeather) {
            artwork = Self.artwork(index: index, weather: weather, snow: snow)
        }
        self.index = index
        self.displayedWeather = displayedWeather
        self.visible = visible
    }
}

/// CD landmark pane's delayed narration. Its timer advances once per distinct
/// active host tick, polls every four ticks, and never catches up missed polls.
struct CDLandmarkAudio {
    private(set) var index: Int?
    private var deadline: UInt32 = 0
    private var lastTick: UInt32 = 0
    private var pollCounter = 0

    mutating func open(index: Int, at tick: UInt32) {
        precondition((0..<18).contains(index))
        self.index = index
        recreate(at: tick)
    }

    /// A Conditions weather redraw recreates an existing pane without stopping
    /// the shared channel. Snow/model changes alone do not call this operation.
    mutating func recreate(at tick: UInt32) {
        guard index != nil else { return }
        deadline = tick &+ 60
        lastTick = tick
        pollCounter = 0
    }

    mutating func close() -> [OriginalAudioQueue.Command] {
        guard index != nil else { return [] }
        index = nil
        deadline = 0
        pollCounter = 0
        return [.stop]
    }

    mutating func poll(at tick: UInt32, visible: Bool, active: Bool = true) -> [OriginalAudioQueue.Command] {
        guard let index, active, tick > lastTick else { return [] }
        lastTick = tick
        pollCounter += 1
        guard pollCounter == 4 else { return [] }
        pollCounter = 0
        guard visible, deadline != 0, tick > deadline else { return [] }
        deadline = 0
        // The source requests even when busy or muted, consuming this opening's
        // deadline once; the existing shared queue decides what actually plays.
        return [.start(1000 + index)]
    }
}
