import Foundation

/// Classic CODE3:0234–0b98 / CD CODE4:01ea–0b34. Pages are STR#3150 indexes.
struct OriginalGuide {
    enum AudioAction: Equatable { case none, stop, request(Int) }
    static let visibleIndexRows = 11
    let edition: GameEdition
    private(set) var page: Int
    private(set) var selection: Int
    private(set) var showingIndex = false
    private var narrationRequested = false

    var pageCount: Int { Self.pageCount(for: edition) }
    var hasNarration: Bool { edition == .macintoshCD12 }
    static func pageCount(for edition: GameEdition) -> Int { edition == .macintoshCD12 ? 73 : 61 }

    init(locationID: String, edition: GameEdition = .macintosh11) {
        self.edition = edition
        // Native Journey.locationID is the last reached landmark, including
        // while traveling and after skipping a branch stop. This is already the
        // result of CODE3:0934 / CD CODE4:0880's destination/distance/flag logic.
        // Blue Mountains deliberately opens Grande Ronde. CD Oregon is page72.
        let pages: [String: (classic: Int, cd: Int)] = [
            "independence": (33,35), "kansas": (37,40), "big-blue": (7,8),
            "kearney": (26,28), "chimney": (13,14), "laramie": (27,29), "rock": (34,36),
            "south-pass": (54,64), "bridger": (24,26), "green": (32,34), "soda": (53,63),
            "hall": (25,27), "snake": (52,62), "boise": (23,25), "blue-mountains": (30,32),
            "walla": (28,30), "dalles": (17,18), "oregon": (61,72)]
        let topic = pages[locationID]
        page = (edition == .macintoshCD12 ? topic?.cd : topic?.classic) ?? 1
        selection = page
    }

    var textResource: Int { 3151 + (page - 1) / 3 }
    var textResourceEntry: Int { 1 + (page - 1) % 3 }
    // CODE3:06aa prepends one space to the single-digit page numbers.
    var pageLabel: String { (page < 10 ? " " : "") + "\(page) of \(pageCount)" }
    var initialIndexRow: Int { min(selection - 1, pageCount - Self.visibleIndexRows) }

    @discardableResult mutating func turn(forward: Bool) -> AudioAction {
        let next = min(pageCount, max(1, page + (forward ? 1 : -1)))
        guard next != page else { return .none }
        page = next
        return close()
    }
    @discardableResult mutating func openIndex() -> AudioAction {
        selection = page
        showingIndex = true
        return close()
    }
    mutating func select(_ page: Int) { selection = min(pageCount, max(1, page)) }
    mutating func closeIndex(accept: Bool) {
        if accept { page = selection }
        showingIndex = false
    }

    /// CD CODE4:03c6 checks both its request marker and the shared sound channel.
    /// A completed (or muted) request can be played again on the next click.
    mutating func toggleNarration(isAudioPlaying: Bool) -> AudioAction {
        guard hasNarration else { return .none }
        if narrationRequested && isAudioPlaying { return close() }
        narrationRequested = true
        return .request(6000 + page)
    }

    @discardableResult mutating func close() -> AudioAction {
        narrationRequested = false
        return hasNarration ? .stop : .none
    }

    /// CDEF8:0294–0316 splits the square along its top-left/bottom-right diagonal.
    static func turnsForward(x: Double, y: Double) -> Bool { y > x }

    /// The actual 9×35 vertical word image embedded at CDEF14:0180–0246.
    static let indexBitmap: [UInt16] = [
        0x8080, 0xff80, 0xff80, 0x8080, 0x0000, 0x8400, 0xfc00,
        0xfc00, 0x8400, 0x0400, 0xfc00, 0xf800, 0x8000, 0x7000,
        0xfc00, 0x8400, 0x8400, 0x8480, 0xff80, 0xff80, 0x8000,
        0x7000, 0xf800, 0xd400, 0x9400, 0x9c00, 0x5800, 0x0000,
        0x8400, 0xcc00, 0x3c00, 0xbc00, 0xf800, 0xc400, 0x8400
    ]
}
