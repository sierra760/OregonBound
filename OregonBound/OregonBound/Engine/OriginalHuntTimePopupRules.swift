/// CODE15:1650/191e, MENU52, System7 MDEF0/MBDF0; Roman Chicago12 branch.
enum OriginalHuntTimePopupRules {
    struct Point: Equatable { var x: Int; var y: Int }
    struct Rect: Equatable {
        var x: Int; var y: Int; var width: Int; var height: Int
        func contains(_ p: Point) -> Bool {
            p.x >= x && p.x < x+width && p.y >= y && p.y < y+height
        }
    }
    static let titles = ["20 seconds","30 seconds","45 seconds","60 seconds","90 seconds","2 minutes"]
    static let label = "Hunt Time:"
    static let checkmark = "\u{12}" // Chicago's original checkmark character.
    // Coordinates are relative to the complete Time Options dialog, not the view.
    static let labelOrigin = Point(x:13,y:133) // Baseline145, ascent12.
    static let box = Rect(x:86,y:130,width:108,height:20)
    static let labelHighlight = Rect(x:8,y:130,width:78,height:20)
    static let selectionOrigin = Point(x:101,y:133)
    static let rowHeight = 16
    static let menuWidth = 97 // widest73 + space4 + adjusted widMax12 + padding8.

    /// MDEF0:0e24–0eaa places the selected row at the supplied top coordinate.
    /// Six rows fit inside the original main device; screen-edge scrolling is not needed here.
    static func menuRect(selection: Int) -> Rect {
        precondition((1...6).contains(selection))
        return .init(x:box.x,y:box.y-(selection-1)*rowHeight,width:menuWidth,height:6*rowHeight)
    }
    /// MDEF0:0234–02a6 uses half-open content bounds and strictly-greater row bottoms.
    static func item(at point: Point, selection: Int) -> Int? {
        let rect = menuRect(selection:selection)
        guard rect.contains(point) else { return nil }
        return (point.y-rect.y)/rowHeight+1
    }
    struct State: Equatable {
        private(set) var isTracking = false
        private(set) var originalSelection = 1
        private(set) var highlightedItem: Int?
        mutating func press(at point: Point, selection: Int) {
            guard (1...6).contains(selection), box.contains(point), !isTracking else { return }
            originalSelection = selection
            isTracking = true
            highlightedItem = OriginalHuntTimePopupRules.item(at:point,selection:selection)
        }
        mutating func drag(to point: Point) {
            guard isTracking else { return }
            highlightedItem = OriginalHuntTimePopupRules.item(at:point,selection:originalSelection)
        }
        /// CODE15:19b0–19e6 accepts only a positive, changed item. Nil leaves value unchanged.
        mutating func release(at point: Point) -> Int? {
            guard isTracking else { return nil }
            drag(to:point)
            let changed = highlightedItem.flatMap { $0 == originalSelection ? nil : $0 }
            cancel()
            return changed
        }
        mutating func cancel() { isTracking = false; highlightedItem = nil }
    }
}
