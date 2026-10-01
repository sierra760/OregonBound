import SwiftUI

/// CODE14's eight-line viewport. Modern wheel/touch input is a native adaptation;
/// arrow/page sizes, text fragments and conditional following use recovered rules.
struct OriginalJournalPane: View {
    let entries: [JournalEntry]
    let departureMonth: Int
    private struct Row {
        let key: String
        let glyphs: [BitmapFont.Placement]
        let x: Int
        let text: String
    }
    @State private var rows: [Row] = []
    @State private var scroll = OriginalJournalScrollState()
    @State private var touchOrigin: Int?

    private var tick: UInt32 { UInt32(truncatingIfNeeded: UInt64(ProcessInfo.processInfo.systemUptime * 60)) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            OriginalPaneFrame(width: 262, height: 102)
            Canvas { context, _ in
                let start = min(scroll.topLine, rows.count)
                let end = min(rows.count, start + OriginalJournalScrollState.visibleLines)
                for index in start..<end {
                    for glyph in rows[index].glyphs {
                        let rect = glyph.rect.offsetBy(dx: CGFloat(rows[index].x), dy: CGFloat(OriginalJournalLayout.firstGlyphTop + OriginalJournalLayout.lineHeight * (index - start)))
                        context.draw(Image(decorative: glyph.image, scale: 1).interpolation(.none), in: rect)
                    }
                }
            }
            .frame(width: CGFloat(OriginalJournalLayout.contentWidth), height: CGFloat(OriginalJournalLayout.contentHeight)).clipped()
            .accessibilityLabel(rows.dropFirst(scroll.topLine).prefix(OriginalJournalLayout.visibleLines).map(\.text).joined(separator: "\n"))
            #if os(macOS)
            // A background NSView loses wheel hit testing to the Canvas host.
            .overlay(JournalWheelInput { delta in select(scroll.topLine + delta) })
            #else
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                if touchOrigin == nil { touchOrigin = scroll.topLine }
                select((touchOrigin ?? scroll.topLine) - Int(value.translation.height / CGFloat(OriginalJournalLayout.lineHeight)))
            }.onEnded { _ in touchOrigin = nil })
            #endif
            OriginalJournalScrollControl(state: scroll, select: select, activate: { part in
                scroll.activate(part, tick: tick)
            }).offset(x: 247, y: -1)
        }
        .frame(width: 262, height: 102, alignment: .topLeading)
        .onAppear { rebuild(entries: entries, initial: true) }
        // Use the delivered entries; this callback can retain the previous view value.
        .onChange(of: entries) { updatedEntries in rebuild(entries: updatedEntries, initial: false) }
    }

    private func select(_ line: Int) { scroll.select(topLine: line, tick: tick) }

    private func rebuild(entries: [JournalEntry], initial: Bool) {
        var output: [Row] = []
        func append(_ text: String, key: String, bold: Bool) {
            guard let font = bold ? BitmapFont.bold12 : BitmapFont.plain12 else { return }
            if let layout = font.journalRecordLayout(text, isBold: bold) {
                for (index, fragment) in layout.fragments.enumerated() {
                    output.append(Row(key: "\(key)-\(index)", glyphs: font.layout(fragment.drawingText).glyphs,
                                      x: fragment.x, text: fragment.drawingText))
                }
            } else {
                // Old native saves can contain text unavailable to the original
                // Pascal/Mac Roman renderer. Keep their safe native wrapping,
                // clipped to four display lines; the full saved text is retained.
                let fallback = font.layout(text, maxWidth: 241)
                for index in 0..<min(4, max(1, Int(fallback.size.height) / font.lineHeight)) {
                    let top = CGFloat(index * font.lineHeight)
                    let glyphs = fallback.glyphs.filter { $0.rect.minY == top }.map {
                        BitmapFont.Placement(image: $0.image, rect: $0.rect.offsetBy(dx: 0, dy: -top))
                    }
                    output.append(Row(key: "\(key)-\(index)", glyphs: glyphs, x: 3, text: index == 0 ? text : ""))
                }
            }
        }
        for (index, entry) in entries.enumerated() {
            if index == 0 || entries[index - 1].day != entry.day {
                let date = OriginalCalendar.date(departureMonth: departureMonth, daysElapsed: entry.day).text
                append("• \(date) •", key: "date-\(entry.day)", bold: false)
            }
            append(entry.text, key: "entry-\(entry.id)", bold: entry.originalBold == true)
        }
        if initial {
            scroll = OriginalJournalScrollState(totalLines: output.count, topLine: max(0, output.count - 8))
        } else if output.count >= rows.count && Array(output.prefix(rows.count).map(\.key)) == rows.map(\.key) {
            scroll.append(totalLines: output.count, hasNewRecords: output.last?.key != rows.last?.key, tick: tick)
        } else {
            // Native saves currently retain500 records, unlike the original byte
            // buffer. Anchor the same visible row when that native cap evicts it.
            let wasAtBottom = scroll.topLine == scroll.maximum
            let anchor = rows.indices.contains(scroll.topLine) ? rows[scroll.topLine].key : nil
            let top = wasAtBottom ? max(0, output.count - 8) : output.firstIndex { $0.key == anchor } ?? 0
            scroll = OriginalJournalScrollState(totalLines: output.count, topLine: top, lastScrollTick: scroll.lastScrollTick)
        }
        rows = output
    }
}

private struct OriginalJournalScrollControl: View {
    let state: OriginalJournalScrollState
    let select: (Int) -> Void
    let activate: (OriginalClassicScrollBar.Part) -> Void
    @State private var pressed: OriginalClassicScrollBar.Part = .none
    @State private var insidePressed = false
    @State private var dragOrigin: Int?
    @State private var previewOrigin: Int?
    private var geometry: OriginalClassicScrollBar.Geometry {
        OriginalClassicScrollBar.geometry(bounds: .init(top: 0, left: 0, bottom: 104, right: 16),
                                          maximum: state.maximum, value: state.topLine)
    }
    var body: some View {
        Canvas { context, _ in
            let enabled = state.maximum > 0
            context.fill(Path(CGRect(x: 0, y: 0, width: 16, height: 104)),
                         with: .color(Color(white: 238.0 / 255)))
            if enabled, let track = OriginalScrollbarArtwork.track {
                // QuickDraw patterns are anchored to the port, not each tile.
                var tiled = context
                tiled.clip(to: Path(CGRect(x: 1, y: 16, width: 14, height: 72)))
                let phaseX = (OriginalJournalLayout.rootX + 247) % 8
                let phaseY = (OriginalJournalLayout.rootY - 1) % 8
                for y in stride(from: -phaseY, to: 104, by: 8) {
                    for x in stride(from: -phaseX, to: 16, by: 8) {
                        tiled.draw(Image(decorative: track, scale: 1).interpolation(.none),
                                   in: CGRect(x: x, y: y, width: 8, height: 8))
                    }
                }
            }
            for down in [false, true] {
                let part: OriginalClassicScrollBar.Part = down ? .increase : .decrease
                if let arrow = OriginalScrollbarArtwork.arrow(down: down, pressed: pressed == part && insidePressed, enabled: enabled) {
                    context.draw(Image(decorative: arrow, scale: 1).interpolation(.none),
                                 in: CGRect(x: 0, y: down ? 88 : 0, width: 16, height: 16))
                }
            }
            if enabled, let thumb = OriginalScrollbarArtwork.thumb {
                context.draw(Image(decorative: thumb, scale: 1).interpolation(.none),
                             in: CGRect(x: 1, y: geometry.thumbOrigin, width: 14, height: 16))
                if let previewOrigin {
                    // The exact Control Manager drag-region raster remains unverified.
                    let outline = CGRect(x: 1.5, y: Double(previewOrigin) + 0.5, width: 13, height: 15)
                    context.stroke(Path(outline), with: .color(.black), lineWidth: 1)
                }
            }
            context.stroke(Path(CGRect(x: 0.5, y: 0.5, width: 15, height: 103)), with: .color(.black), lineWidth: 1)
        }
        .frame(width: 16, height: 104).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            if pressed == .none {
                pressed = OriginalClassicScrollBar.hitTest(.init(x: Int(value.startLocation.x), y: Int(value.startLocation.y)), geometry: geometry)
                if pressed == .thumb { dragOrigin = geometry.thumbOrigin }
                else { activate(pressed) }
            }
            insidePressed = OriginalClassicScrollBar.hitTest(.init(x: Int(value.location.x), y: Int(value.location.y)), geometry: geometry) == pressed
            if pressed == .thumb, let origin = dragOrigin {
                previewOrigin = min(72, max(16, origin + Int(value.translation.height)))
            }
        }.onEnded { value in
            if pressed == .thumb, let origin = dragOrigin {
                select(OriginalClassicScrollBar.valueForThumbOrigin(origin + Int(value.translation.height), geometry: geometry))
            }
            pressed = .none; insidePressed = false; dragOrigin = nil; previewOrigin = nil
        })
        .accessibilityElement(children: .ignore).accessibilityLabel("Trail journal scroll position")
        .accessibilityValue("\(state.topLine + 1) of \(max(1, state.totalLines))")
        .accessibilityAdjustableAction { activate($0 == .increment ? .increase : .decrease) }
        .accessibilityAction(named: "Previous page") { activate(.pageDecrease) }
        .accessibilityAction(named: "Next page") { activate(.pageIncrease) }
    }
}

#if os(macOS)
struct JournalWheelInput: NSViewRepresentable {
    let scroll: (Int) -> Void
    final class View: NSView {
        var action: ((Int) -> Void)?
        private var remainder: CGFloat = 0
        override func scrollWheel(with event: NSEvent) {
            remainder -= event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
            let lines = Int(remainder)
            if lines != 0 { remainder -= CGFloat(lines); action?(lines) }
        }
    }
    func makeNSView(context: Context) -> View { let view = View(); view.action = scroll; return view }
    func updateNSView(_ view: View, context: Context) { view.action = scroll }
}
#endif
