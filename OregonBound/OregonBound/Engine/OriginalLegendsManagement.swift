/// CODE15:06cc–0a3e. Only the single-wagon table (selector0) is edited here.
enum OriginalLegendsManagement {
    struct Editor {
        private(set) var rows: [OriginalEndingPresentation.Legend]
        private(set) var selected: Set<String> = []
        private(set) var pendingRemovals: [OriginalEndingPresentation.Legend] = []
        private var anchor: Int?
        init(legends: [OriginalEndingPresentation.Legend]) { rows = legends }
        mutating func select(_ index: Int, extending: Bool = false, range: Bool = false) {
            guard rows.indices.contains(index) else { return }
            if range, let anchor, rows.indices.contains(anchor) {
                selected.formUnion(rows[min(anchor, index)...max(anchor, index)].map(\.id))
            } else if extending {
                if !selected.insert(rows[index].id).inserted { selected.remove(rows[index].id) }
                anchor = index
            } else {
                selected = [rows[index].id]
                anchor = index
            }
        }
        mutating func selectAll() { selected = Set(rows.map(\.id)) }
        mutating func removeSelected() {
            pendingRemovals.append(contentsOf: rows.filter { selected.contains($0.id) })
            rows.removeAll { selected.contains($0.id) }
            selected.removeAll()
            anchor = nil
        }
        /// CODE15 does not clear D6/the pending list after Original+Yes.
        mutating func restored(_ originals: [OriginalEndingPresentation.Legend]) {
            rows = originals
            selected.removeAll()
            anchor = nil
        }
    }
}
