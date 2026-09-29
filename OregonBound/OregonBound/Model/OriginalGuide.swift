import Foundation

/// CODE3:0234–0b98. Guide pages are one-based STR#3150 indexes, not text slices.
struct OriginalGuide {
    static let pageCount = 61
    static let visibleIndexRows = 11
    private(set) var page: Int
    private(set) var selection: Int
    private(set) var showingIndex = false

    init(locationID: String) {
        // CODE3:0934 selects the last reached landmark while on a leg. The
        // Blue Mountains stop deliberately opens Grande Ronde, not topic 9.
        let pages = ["independence": 33, "kansas": 37, "big-blue": 7,
                     "kearney": 26, "chimney": 13, "laramie": 27, "rock": 34,
                     "south-pass": 54, "bridger": 24, "green": 32, "soda": 53,
                     "hall": 25, "snake": 52, "boise": 23, "blue-mountains": 30,
                     "walla": 28, "dalles": 17, "oregon": 61]
        page = pages[locationID] ?? 1
        selection = page
    }

    var textResource: Int { 3151 + (page - 1) / 3 }
    var textResourceEntry: Int { 1 + (page - 1) % 3 }
    // CODE3:06aa prepends one space to the single-digit page numbers.
    var pageLabel: String { (page < 10 ? " " : "") + "\(page) of 61" }
    var initialIndexRow: Int { min(selection - 1, Self.pageCount - Self.visibleIndexRows) }

    mutating func turn(forward: Bool) { page = min(Self.pageCount, max(1, page + (forward ? 1 : -1))) }
    mutating func openIndex() { selection = page; showingIndex = true }
    mutating func select(_ page: Int) { selection = min(Self.pageCount, max(1, page)) }
    mutating func closeIndex(accept: Bool) {
        if accept { page = selection }
        showingIndex = false
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
