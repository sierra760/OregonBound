import SwiftUI
#if os(macOS)
import AppKit

/// On macOS the SwiftUI content geometry stays in the hosting view's local
/// coordinates while NSClipView scrolls. Observe that actual clip origin.
private struct GuideScrollPosition: NSViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.changed = changed
        return view
    }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.changed = changed
        DispatchQueue.main.async { view.attach() }
    }
    final class ObserverView: NSView {
        var changed: ((CGFloat) -> Void)?
        private weak var clip: NSClipView?
        private var observation: NSObjectProtocol?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { self.attach() }
        }
        func attach() {
            guard let content = enclosingScrollView?.contentView else { return }
            if clip !== content {
                if let observation { NotificationCenter.default.removeObserver(observation) }
                clip = content
                content.postsBoundsChangedNotifications = true
                observation = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: content, queue: .main) { [weak self] _ in self?.report() }
            }
            report()
        }
        private func report() {
            if let clip { changed?(clip.bounds.minY) }
        }
        deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    }
}
#endif

/// DITL6020/6170, CODE3:0234–0b98, and the original CDEF8/14 controls.
struct OriginalGuidePane: View {
    @State private var guide: OriginalGuide
    let audio: GameAudio

    init(trip: Journey, audio: GameAudio = .shared, initialPage: Int? = nil) {
        self.audio = audio
        _guide = State(initialValue: OriginalGuide(locationID: trip.locationID, edition: GameData.edition, initialPage: initialPage))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if guide.showingIndex {
                OriginalGuideIndex(selection: guide.selection, initialRow: guide.initialIndexRow, pageCount: guide.pageCount,
                                   select: { guide.select($0) },
                                   accept: { guide.closeIndex(accept: true) },
                                   cancel: { guide.closeIndex(accept: false) })
            } else {
                page
            }
        }.frame(width: 262, height: 199).clipped()

    }

    private var page: some View {
        ZStack(alignment: .topLeading) {
            PixelArtwork(resource: 16010, monochromeResource: 6010).frame(width: 23, height: 199).offset(x: 239)
            if let entry = OriginalResources.guide.first(where: { $0.id == guide.page - 1 }) {
                OriginalText(text: entry.title, font: .bold14)
                    .frame(width: 198, height: 18, alignment: .topLeading).clipped().offset(x: 6, y: 10)
                // CODE3:07f4 uses TETextBox with a 230×160 rectangle. The authored
                // text fits the DITL item; neither scroll bars nor repagination occur.
                OriginalText(text: entry.text, font: .plain12, width: 230)
                    .frame(width: guide.hasNarration ? 231 : 230, height: guide.hasNarration ? 143 : 142, alignment: .topLeading).clipped().offset(x: 6, y: 39)
            }
            Rectangle().fill(.black).frame(width: 198, height: 1).offset(x: 6, y: 32)
            OriginalText(text: guide.pageLabel, font: .plain12).offset(x: 93, y: 186)
            OriginalGuideFold { audio.perform(guide.turn(forward: $0)) }.offset(x: 208)
            OriginalGuideIndexTab { audio.perform(guide.openIndex()) }.offset(x: 241, y: 126)
            if guide.hasNarration {
                Button {
                    audio.perform(guide.toggleNarration(isAudioPlaying: audio.isPlaying))
                } label: {
                    // DITL6020 item8 stretches cicn6003 into its 32×30 item rect.
                    OriginalResources.image(6003, type: OriginalResources.iconType)?
                        .resizable().interpolation(.none).frame(width: 32, height: 30)
                }.buttonStyle(.plain).accessibilityLabel("Play or stop guide narration")
                    .offset(x: 205, y: 169)
            }
        }.frame(width: 262, height: 199, alignment: .topLeading)
    }
}

private struct GuideTriangle: Shape {
    let forward: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: forward ? CGPoint(x: rect.minX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct OriginalGuideFold: View {
    let turn: (Bool) -> Void
    @GestureState private var pressedPoint: CGPoint?
    private var pressedPart: Bool? {
        guard let point = pressedPoint, point.x >= 0, point.y >= 0, point.x < 32, point.y < 32 else { return nil }
        return OriginalGuide.turnsForward(x: floor(point.x), y: floor(point.y))
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            originalPaper
            if let pressedPart { GuideTriangle(forward: pressedPart).fill(.black) }
            Canvas { context, _ in
                for rect in [CGRect(x: 0, y: 0, width: 32, height: 1), CGRect(x: 0, y: 31, width: 32, height: 1),
                             CGRect(x: 0, y: 0, width: 1, height: 32), CGRect(x: 31, y: 0, width: 1, height: 32)] {
                    context.fill(Path(rect), with: .color(.black))
                }
                for pixel in 1...30 { context.fill(Path(CGRect(x: pixel, y: pixel, width: 1, height: 1)), with: .color(.black)) }
            }.allowsHitTesting(false)
        }.frame(width: 32, height: 32).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressedPoint) { value, point, _ in point = value.location }
                .onEnded { value in
                    let point = value.location
                    guard point.x >= 0, point.y >= 0, point.x < 32, point.y < 32 else { return }
                    turn(OriginalGuide.turnsForward(x: floor(point.x), y: floor(point.y)))
                })
            .accessibilityElement(children: .ignore).accessibilityLabel("Guide page turn")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { turn(true) }
            .accessibilityAction(named: "Next guide page") { turn(true) }
            .accessibilityAction(named: "Previous guide page") { turn(false) }
    }
}

private struct OriginalGuideIndexTab: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Color.clear.frame(width: 18, height: 48) }
            .buttonStyle(GuideIndexTabStyle()).accessibilityLabel("Guide index")
    }
}

private struct GuideIndexTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Canvas { context, _ in
            // CDEF14 doubles the rect's width, frames a round rect with an oval
            // size equal to its height, and clips that drawing to its left half.
            let round = Path(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 35, height: 47))
            context.fill(round, with: .color(configuration.isPressed ? .black : originalPaper))
            context.stroke(round, with: .color(.black), lineWidth: 1)
            context.fill(Path(CGRect(x: 17, y: 0, width: 1, height: 48)), with: .color(.black))
            // Destination is x = right - (width-9)/4 - 9, y = top + (height-35)/2.
            for (y, row) in OriginalGuide.indexBitmap.enumerated() {
                for x in 0..<9 where row & (UInt16(0x8000) >> x) != 0 {
                    context.fill(Path(CGRect(x: 7 + x, y: 6 + y, width: 1, height: 1)),
                                 with: .color(configuration.isPressed ? originalPaper : .black))
                }
            }
        }.frame(width: 18, height: 48).clipped()
            .contentShape(GuideIndexTabShape())
    }
}

private struct GuideIndexTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 18, y: 0))
            path.addCurve(to: CGPoint(x: 0, y: 24), control1: CGPoint(x: 8.059, y: 0), control2: CGPoint(x: 0, y: 10.745))
            path.addCurve(to: CGPoint(x: 18, y: 48), control1: CGPoint(x: 0, y: 37.255), control2: CGPoint(x: 8.059, y: 48))
            path.closeSubpath()
        }
    }
}

private struct GuideIndexOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct OriginalGuideIndex: View {
    let selection: Int
    let initialRow: Int
    var pageCount = 61
    private var maximumRow: Int { max(0, pageCount - OriginalGuide.visibleIndexRows) }
    let select: (Int) -> Void
    let accept: () -> Void
    let cancel: () -> Void
    @State private var topRow: CGFloat = 0
    private let rowHeight: CGFloat = 15

    var body: some View {
        ZStack(alignment: .topLeading) {
            OriginalText(text: "What would you like to read about?", font: .plain14).offset(x: 6, y: 6)
            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(OriginalResources.guide) { entry in
                                OriginalText(text: entry.title, font: .plain12)
                                    .modifier(GuideSelectionInk(selected: selection == entry.id + 1))
                                    .offset(x: 2, y: 3)
                                    .frame(width: 131, height: rowHeight, alignment: .topLeading)
                                    .background(selection == entry.id + 1 ? Color.black : originalPaper)
                                    .contentShape(Rectangle()).clipped()
                                    .onTapGesture(count: 2) { select(entry.id + 1); accept() }
                                    .onTapGesture { select(entry.id + 1) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAddTraits(selection == entry.id + 1 ? .isSelected : [])
                                    .accessibilityAction { select(entry.id + 1) }
                                    .id(entry.id)
                            }
                        }
                        #if os(macOS)
                        .background(GuideScrollPosition { y in
                            let row = min(CGFloat(maximumRow), max(0, y / rowHeight))
                            if topRow != row { topRow = row }
                        })
                        #else
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: GuideIndexOffset.self,
                                                   value: -geometry.frame(in: .named("guideIndex")).minY / rowHeight)
                        })
                        #endif
                    }
                        .frame(width: 131, height: 165).offset(x: 1, y: 1)
                        #if !os(macOS)
                        .onPreferenceChange(GuideIndexOffset.self) { topRow = min(CGFloat(maximumRow), max(0, $0)) }
                        #endif
                    GuideIndexScrollBar(topRow: topRow, pageCount: pageCount) { row in
                        proxy.scrollTo(min(maximumRow, max(0, row)), anchor: .top)
                    }.offset(x: 132)
                    Rectangle().strokeBorder(.black, lineWidth: 1).allowsHitTesting(false)
                }.frame(width: 148, height: 167).coordinateSpace(name: "guideIndex")
                    .onAppear { proxy.scrollTo(initialRow, anchor: .top) }
            }.frame(width: 148, height: 167).offset(x: 6, y: 29)
            OriginalButton(title: "Cancel", action: cancel)
                .frame(width: 80, height: 20).offset(x: 166, y: 130).keyboardShortcut(.cancelAction)
            OriginalButton(title: "OK", isDefault: true, action: accept)
                .frame(width: 80, height: 20).offset(x: 167, y: 160).keyboardShortcut(.defaultAction)
        }.frame(width: 262, height: 199, alignment: .topLeading)
    }
}

private struct GuideSelectionInk: ViewModifier {
    let selected: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if selected { content.colorInvert() } else { content }
    }
}

private struct GuideIndexButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(GuideSelectionInk(selected: configuration.isPressed))
    }
}

/// Original standard scrollbar proportions: 16px wide, 16px arrows and thumb.
private struct GuideIndexScrollBar: View {
    let topRow: CGFloat
    let pageCount: Int
    let scroll: (Int) -> Void
    @State private var dragOrigin: CGFloat?
    private var geometry: OriginalClassicScrollBar.Geometry {
        OriginalClassicScrollBar.geometry(bounds: .init(top: 0, left: 0, bottom: 167, right: 16),
                                          maximum: max(0, pageCount - OriginalGuide.visibleIndexRows), value: Int(topRow))
    }
    private var thumbY: CGFloat { CGFloat(geometry.thumbOrigin) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: 16, height: 167)), with: .color(.white))
                for y in 16..<151 {
                    for x in 1..<15 where (x + y) % 2 == 0 {
                        context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black))
                    }
                }
            }.gesture(DragGesture(minimumDistance: 0).onEnded { value in
                if value.location.y < thumbY { scroll(Int(topRow) - 11) }
                else if value.location.y > thumbY + 16 { scroll(Int(topRow) + 11) }
            })
            arrow(down: false) { scroll(Int(topRow) - 1) }
            arrow(down: true) { scroll(Int(topRow) + 1) }.offset(y: 151)
            Rectangle().fill(.white).frame(width: 14, height: 16)
                .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                .overlay {
                    Canvas { context, _ in
                        for y in stride(from: 3, through: 12, by: 2) {
                            context.fill(Path(CGRect(x: 2, y: y, width: 10, height: 1)), with: .color(.gray))
                        }
                    }.allowsHitTesting(false)
                }
                .offset(x: 1, y: thumbY)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = thumbY }
                        let origin = Int((dragOrigin ?? thumbY) + value.translation.height)
                        scroll(OriginalClassicScrollBar.valueForThumbOrigin(origin, geometry: geometry))
                    }.onEnded { _ in dragOrigin = nil })
                .accessibilityLabel("Guide index scroll position")
                .accessibilityValue("\(Int(topRow) + 1) of \(pageCount)")
                .accessibilityAdjustableAction { direction in scroll(Int(topRow) + (direction == .increment ? 1 : -1)) }
        }.frame(width: 16, height: 167)
    }
    private func arrow(down: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: 16, height: 16)), with: .color(.white))
                context.stroke(Path(CGRect(x: 0.5, y: 0.5, width: 15, height: 15)), with: .color(.black), lineWidth: 1)
                var path = Path()
                let points: [(CGFloat, CGFloat)] = [(3, 8), (7, 4), (11, 8), (9, 8), (9, 11), (5, 11), (5, 8)]
                for (index, p) in points.enumerated() {
                    let point = CGPoint(x: p.0 + 0.5, y: (down ? 15 - p.1 : p.1) + 0.5)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.black), lineWidth: 1)
            }.frame(width: 16, height: 16)
        }.buttonStyle(GuideIndexButtonStyle()).accessibilityLabel(down ? "Scroll index down" : "Scroll index up")
    }
}
