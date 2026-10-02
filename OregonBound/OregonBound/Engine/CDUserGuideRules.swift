import Foundation

/// Navigation of the separate MECC Reader document. None of these actions has
/// access to a journey, random stream, audio channel or game preferences.
enum CDUserGuideRules {
    /// A native two-pane equivalent of the reader's multiple document windows.
    /// Page, zoom and pan are per view; Return history belongs to the document.
    struct Views {
        private(set) var states: [State]
        init(state: State) { states = [state] }
        mutating func openComparison() {
            guard states.count == 1 else { return }
            var copy = states[0]; copy.dismissCaption(); states.append(copy)
        }
        mutating func closeComparison() {
            if states.count == 2 { states.removeLast() }
        }
        mutating func update(_ index: Int, _ action: (inout State) -> Void) {
            guard states.indices.contains(index) else { return }
            action(&states[index])
            let history = states[index].history
            for i in states.indices { states[i].history = history }
        }
    }
    struct Point: Equatable {
        let x: Int
        let y: Int
        static let zero = Point(x: 0, y: 0)
    }
    struct HistoryEntry: Equatable {
        let pageID: Int
        let offset: Point
    }
    struct State {
        let guide: CDUserGuide
        private(set) var pageIndex = 0
        private(set) var zoomTenths = 10
        private(set) var offset = Point.zero
        private(set) var viewportWidth: Int
        private(set) var viewportHeight: Int
        fileprivate(set) var history: [HistoryEntry] = []
        private(set) var caption: CDUserGuide.Link?
        var pageID: Int { guide.pageIDs[pageIndex] }
        var sectionIndex: Int {
            guide.sections.firstIndex { $0.firstPage <= pageIndex + 1 && $0.lastPage >= pageIndex + 1 } ?? 0
        }
        var maximumOffset: Point {
            Point(x: max(0, 612 * zoomTenths / 10 - viewportWidth),
                  y: max(0, 792 * zoomTenths / 10 - viewportHeight))
        }
        var pageNumber: String {
            let page = pageIndex + 1
            var count = 0, sign = 1
            for section in guide.sections {
                if section.numbering != -128 {
                    count = 0
                    sign = section.numbering == 0 ? 0 : (section.numbering == 2 ? -1 : 1)
                }
                if page <= section.lastPage {
                    let value = sign * (count + page - section.firstPage + 1)
                    if value == 0 { return "" }
                    if value > 0 { return String(value) }
                    return Self.roman(-value)
                }
                count += section.lastPage - section.firstPage + 1
            }
            return ""
        }
        private static func roman(_ value: Int) -> String {
            guard value < 100 else { return "" } // Original formatter's limit.
            var value = value, result = ""
            for (amount, letters) in [(90, "XC"), (50, "L"), (40, "XL"), (10, "X"),
                                      (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
                while value >= amount { result += letters; value -= amount }
            }
            return result
        }

        init(guide: CDUserGuide, viewportWidth: Int = 612, viewportHeight: Int = 600) {
            self.guide = guide
            self.viewportWidth = min(8192, max(1, viewportWidth))
            self.viewportHeight = min(8192, max(1, viewportHeight))
        }
        mutating func resize(width: Int, height: Int) {
            viewportWidth = min(8192, max(1, width)); viewportHeight = min(8192, max(1, height))
            setOffset(x: offset.x, y: offset.y)
        }
        mutating func setOffset(x: Int, y: Int) {
            let maximum = maximumOffset
            offset = Point(x: min(maximum.x, max(0, x)), y: min(maximum.y, max(0, y)))
            caption = nil
        }
        mutating func page(forward: Bool) {
            let target = pageIndex + (forward ? 1 : -1)
            guard guide.pageIDs.indices.contains(target) else { return }
            pageIndex = target; offset = .zero; caption = nil
        }
        mutating func screen(forward: Bool) {
            if forward && maximumOffset.y - offset.y < 10 { page(forward: true) }
            else if !forward && pageIndex > 0 && offset.y < 10 {
                page(forward: false); setOffset(x: 0, y: maximumOffset.y)
            } else {
                setOffset(x: offset.x, y: offset.y + (forward ? 1 : -1) * max(1, viewportHeight - 16))
            }
        }
        mutating func setZoom(tenths: Int) {
            guard (5...50).contains(tenths) else { return }
            zoomTenths = tenths; offset = .zero; caption = nil
        }
        mutating func magnify(at point: Point, increase: Bool) {
            guard let paper = paperPoint(at: point) else { return }
            setZoom(tenths: min(50, max(5, zoomTenths + (increase ? 10 : -10))))
            setOffset(x: paper.x * zoomTenths / 10 - viewportWidth / 2,
                      y: paper.y * zoomTenths / 10 - viewportHeight / 2)
        }
        func paperPoint(at point: Point) -> Point? {
            guard (0..<viewportWidth).contains(point.x), (0..<viewportHeight).contains(point.y) else { return nil }
            return Point(x: (point.x + offset.x) * 10 / zoomTenths,
                         y: (point.y + offset.y) * 10 / zoomTenths)
        }
        func linkIndex(at point: Point) -> Int? {
            guard let paper = paperPoint(at: point) else { return nil }
            return guide.links[pageID]?.firstIndex {
                $0.bounds.left <= paper.x && paper.x < $0.bounds.right
                    && $0.bounds.top <= paper.y && paper.y < $0.bounds.bottom
            }
        }
        private mutating func remember() {
            // Keep a bounded recent-location menu in the native reader.
            if history.count == 128 { history.removeFirst() }
            history.append(HistoryEntry(pageID: pageID, offset: offset))
        }
        mutating func chooseSection(at index: Int) {
            guard guide.sections.indices.contains(index) else { return }
            remember()
            let target = guide.sections[index].firstPage - 1
            // Original same-page section selection leaves its scroll position.
            if target != pageIndex { pageIndex = target; offset = .zero }
            caption = nil
        }
        mutating func activateLink(at index: Int) {
            guard let links = guide.links[pageID], links.indices.contains(index) else { return }
            let link = links[index]
            if link.kind == .caption { caption = link; return }
            guard let target = guide.pageIDs.firstIndex(of: link.destination) else { return }
            remember(); pageIndex = target
            setOffset(x: link.destinationRect.left * zoomTenths / 10,
                      y: link.destinationRect.top * zoomTenths / 10)
        }
        mutating func dismissCaption() { caption = nil }
        mutating func returnToHistory(at index: Int? = nil) {
            let index = index ?? history.count - 1
            guard history.indices.contains(index) else { return }
            let entry = history.remove(at: index)
            guard let target = guide.pageIDs.firstIndex(of: entry.pageID) else { return }
            pageIndex = target
            // CODE3:16bc passes the stored pixel offset to the same go-to
            // routine as a topic; CODE3:0dce scales it by the current zoom.
            setOffset(x: entry.offset.x * zoomTenths / 10, y: entry.offset.y * zoomTenths / 10)
        }
    }
}
