/// CODE2/DLOG2001, STR2003/2112/2113, MECC0/4. Runtime machine/memory values
/// must be provided by the integration; they are not authored constants.
enum OriginalAboutRules {
    static let program = "Oregon Bound"
    static let version = "Version: 1.0"
    static let copyright = "Copyright 2026 Sierra Burkhart"
    static let license = "MIT licensed source"
    static let attribution = ["Independent recreation", "Original game: MECC, 1991", "Not affiliated or endorsed.", "Game files supplied by you."]
    static let credits = ["Brian Bezanson", "Sean Callahan", "Craig Copley", "Paul Davis", "Mark Dostal", "Charolyn Kapplinger", "Mark Larson", "Pam Rostal", "Mark Schneider", "Steve Splinter", "Wayne Studer", "Jim Thompson", "Paul Wenker"]
    static let systemLabels = ["Machine Type:", "Processor:", "System Version:", "AppleTalk Version:", "Heap Size:", "Largest Block:", "Free Memory:"]
    /// CD credits idle callback. Requests remain subject to the shared audio
    /// channel's mute and bounded FIFO, including repeated requests while busy.
    struct Audio {
        private var lastTick: UInt32
        private let alternate: Bool
        init(openedAt: UInt32, alternate: Bool) {
            lastTick = openedAt
            self.alternate = alternate
        }
        mutating func poll(at tick: UInt32, showsSystemInformation: Bool) -> Int? {
            guard !showsSystemInformation, Int32(bitPattern: tick &- lastTick) > 2 else { return nil }
            lastTick = tick
            return alternate ? 10000 : 2000
        }
    }

    struct State: Equatable {
        private(set) var showsSystemInformation = false
        private(set) var previousClickTick: UInt32 = 0
        var heading: String { showsSystemInformation ? "System Information:" : "Original game team:" }
        /// Original D7=0 sentinel and signed TickCount comparison, not a new
        /// fixed double-click interval. Host/reference preference supplies it.
        mutating func clickLogo(tick: UInt32, doubleClickTicks: UInt32) {
            if previousClickTick != 0,
               Int32(bitPattern: tick) < Int32(bitPattern: previousClickTick &+ doubleClickTicks) {
                showsSystemInformation.toggle()
                previousClickTick = 0
            } else { previousClickTick = tick }
        }
    }
    struct CreditPosition: Equatable { let index: Int; let x: Int; let baseline: Int }
    static func creditPositions(width: (String) -> Int) -> [CreditPosition] {
        // Thirteen names: first column ceil(13/2)=7; local115-pixel area,
        // Geneva9 ascent+descent12; gap=floor((115-7*12)/7)=4.
        let secondColumn = credits.prefix(7).map(width).max()! + 15
        return credits.indices.map { index in
            CreditPosition(index: index, x: index < 7 ? 0 : secondColumn, baseline: 12 + (index % 7) * 16)
        }
    }
}
