import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import PDFKit
#else
import UIKit
#endif

@MainActor final class CDUserGuideReader: ObservableObject {
    struct Explanation: Identifiable {
        let id = UUID()
        let content: CDGuideDocument.Caption
    }
    let document: CDGuideDocument?
    let unavailable: String?
    @Published private(set) var views: CDUserGuideRules.Views?
    @Published var explanation: Explanation?
    @Published var error: String?
    @Published var exportingPDF = false
    var exportDocument: OriginalTransferDocument?
    var active = true
    private let permitsActions: () -> Bool

    init(guide: CDUserGuide?, fonts: CDGuideFonts?, unavailable: String?, permitsActions: @escaping () -> Bool = { true }) {
        self.permitsActions = permitsActions
        do {
            if let guide {
                document = try CDGuideDocument(guide: guide, originalFonts: fonts)
                views = .init(state: .init(guide: guide)); self.unavailable = nil
            } else {
                document = nil; self.unavailable = unavailable ?? "Import the Deluxe disk image to read its On-line User’s Guide."
            }
        } catch {
            document = nil; self.unavailable = "The user guide could not be opened. \(error)"
        }
    }
    func update(_ index: Int, _ action: (inout CDUserGuideRules.State) -> Void) {
        guard active, permitsActions(), explanation == nil else { return }
        views?.update(index, action)
        if let states = views?.states, states.indices.contains(index), let link = states[index].caption {
            do {
                if let content = try document?.caption(link) { explanation = Explanation(content: content) }
            } catch { self.error = String(describing: error) }
        }
    }
    func compare() {
        guard active, permitsActions(), explanation == nil else { return }
        if views?.states.count == 2 { views?.closeComparison() } else { views?.openComparison() }
    }
    func resize(_ index: Int, size: CGSize) {
        views?.update(index) { $0.resize(width: Int(size.width), height: Int(size.height)) }
    }
    func dismissExplanation() {
        explanation = nil
        for index in views?.states.indices ?? 0..<0 { views?.update(index) { $0.dismissCaption() } }
    }
    func export(_ pages: [Int]) {
        guard active, permitsActions(), explanation == nil, let document else { return }
        do {
            exportDocument = OriginalTransferDocument(data: try document.pdf(pageIndices: pages))
            exportingPDF = true
        } catch { self.error = String(describing: error) }
    }
    func printPages(_ pages: [Int]) {
        guard active, permitsActions(), explanation == nil, let document else { return }
        do {
            let data = try document.pdf(pageIndices: pages)
            #if os(macOS)
            guard let pdf = PDFDocument(data: data),
                  let operation = pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false) else {
                throw CDUserGuide.Failure.invalid("unable to open the print panel")
            }
            operation.run()
            #else
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = "On-line User’s Guide"; info.outputType = .general
            controller.printInfo = info; controller.printingItem = data
            if !controller.present(animated: true, completionHandler: { [weak self] _, _, error in
                if let error { self?.error = error.localizedDescription }
            }) { throw CDUserGuide.Failure.invalid("printing is not available") }
            #endif
        } catch { self.error = String(describing: error) }
    }
}

struct CDUserGuidePane: View {
    @StateObject private var reader: CDUserGuideReader
    @State private var compactView = 0
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    init(guide: CDUserGuide?, fonts: CDGuideFonts?, unavailable: String?, permitsActions: @escaping () -> Bool = { true }, close: @escaping () -> Void) {
        _reader = StateObject(wrappedValue: CDUserGuideReader(guide: guide, fonts: fonts, unavailable: unavailable, permitsActions: permitsActions))
        self.close = close
    }
    init(reader: CDUserGuideReader, close: @escaping () -> Void) {
        _reader = StateObject(wrappedValue: reader); self.close = close
    }
    var body: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("On-line User’s Guide").font(.headline).fixedSize()
                    Spacer(); headerActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("On-line User’s Guide").font(.headline)
                    HStack { headerActions }
                }
            }
            if let document = reader.document, let views = reader.views {
                if !document.usesOriginalFonts {
                    Text("Using substitute fonts. Read page text for the complete transcript. Import the original System file to restore the original typefaces.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                GeometryReader { geometry in
                    if views.states.count == 2 && geometry.size.width >= 900 {
                        HStack(spacing: 16) { columns(views, document: document) }
                    } else if views.states.count == 2 {
                        VStack {
                            Picker("Reader view", selection: $compactView) {
                                Text("Main page").tag(0); Text("Comparison page").tag(1)
                            }.pickerStyle(.segmented)
                            CDUserGuideColumn(reader: reader, document: document, index: compactView,
                                state: views.states[compactView]).id(compactView)
                        }
                    } else {
                        VStack(spacing: 16) { columns(views, document: document) }
                    }
                }
            } else {
                Spacer()
                Text(reader.unavailable ?? "The user guide is unavailable.")
                    .frame(maxWidth: 500).textSelection(.enabled)
                Spacer()
            }
        }
        .padding(16)
        .background(.background)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 1000, minHeight: 620, idealHeight: 820)
        #endif
        .disabled(scenePhase != .active)
        .onAppear { reader.active = scenePhase == .active }
        .onChange(of: scenePhase) { reader.active = $0 == .active }
        .fileExporter(isPresented: $reader.exportingPDF, document: reader.exportDocument,
            contentType: .pdf, defaultFilename: "Oregon Trail User Guide") { result in
                if case .failure(let error) = result { reader.error = error.localizedDescription }
            }
        .sheet(item: $reader.explanation, onDismiss: reader.dismissExplanation) { explanation in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Explanation").font(.headline)
                    Spacer()
                    Button("Done", action: reader.dismissExplanation).keyboardShortcut(.cancelAction)
                }
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: explanation.content.image, scale: 1)
                        .interpolation(.none).accessibilityHidden(true)
                }.frame(maxHeight: 200)
                ScrollView { Text(explanation.content.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(minWidth: 300, idealWidth: 500, minHeight: 250, idealHeight: 450)
        }
        .alert("Unable to display the guide", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
    }

    private func columns(_ views: CDUserGuideRules.Views, document: CDGuideDocument) -> some View {
        ForEach(views.states.indices, id: \.self) { index in
            CDUserGuideColumn(reader: reader, document: document, index: index, state: views.states[index])
        }
    }
    private var headerActions: some View {
        Group {
            if reader.document != nil {
                Menu("Print and export") {
                    outputChoices(printing: false); Divider(); outputChoices(printing: true)
                }
                Button(reader.views?.states.count == 2 ? "Close comparison" : "Compare pages", action: reader.compare)
            }
            Button("Done", action: close).keyboardShortcut(.cancelAction)
        }
    }
    private func outputChoices(printing: Bool) -> some View {
        Group {
            if let views = reader.views, let document = reader.document {
                let action = printing ? "Print" : "Export PDF of"
                Button("\(action) entire guide…") { output(Array(document.guide.pageIDs.indices), printing: printing) }
                Button("\(action) current page…") { output([views.states[0].pageIndex], printing: printing) }
                if views.states.count == 2 {
                    Button("\(action) comparison page…") { output([views.states[1].pageIndex], printing: printing) }
                }
            }
        }
    }
    private func output(_ pages: [Int], printing: Bool) {
        if printing { reader.printPages(pages) } else { reader.export(pages) }
    }
}

private struct CDUserGuideColumn: View {
    @ObservedObject var reader: CDUserGuideReader
    let document: CDGuideDocument
    let index: Int
    let state: CDUserGuideRules.State
    @State private var readText = false
    @State private var dragStart: CDUserGuideRules.Point?
    @State private var tool = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Menu(state.guide.sections[state.sectionIndex].title) {
                    ForEach(state.guide.sections.indices, id: \.self) { section in
                        Button(state.guide.sections[section].title) { update { $0.chooseSection(at: section) } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("Page \(state.pageIndex + 1) of \(state.guide.pageIDs.count)").font(.caption)
            }
            HStack {
                Button { update { $0.page(forward: false) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous page").disabled(state.pageIndex == 0)
                Button { update { $0.page(forward: true) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next page").disabled(state.pageIndex == state.guide.pageIDs.count - 1)
                Button("Return") { update { $0.returnToHistory() } }.disabled(state.history.isEmpty)
                Menu {
                    ForEach(state.history.indices.reversed(), id: \.self) { entry in
                        let page = state.guide.pageIDs.firstIndex(of: state.history[entry].pageID) ?? 0
                        Button("\(entry + 1). Page \(page + 1)") { update { $0.returnToHistory(at: entry) } }
                    }
                } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Return history").disabled(state.history.isEmpty)
                Spacer(minLength: 0)
                Menu("\(state.zoomTenths * 10)%") {
                    ForEach([5, 10, 20, 30, 40, 50], id: \.self) { zoom in
                        Button("\(zoom * 10)%") { update { $0.setZoom(tenths: zoom) } }
                    }
                }.accessibilityLabel("Magnification, \(state.zoomTenths * 10) percent")
            }.buttonStyle(.bordered)
            switch Result(catching: { try document.picture(state.pageID) }) {
            case .success(let picture):
                Menu("Links and explanations") {
                    ForEach(Array((state.guide.links[state.pageID] ?? []).enumerated()), id: \.offset) { item in
                        Button(linkLabel(item.element, picture: picture, index: item.offset)) {
                            update { $0.activateLink(at: item.offset) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .disabled((state.guide.links[state.pageID] ?? []).isEmpty)
                viewport(picture)
                HStack {
                    Button("Previous screen") { update { $0.screen(forward: false) } }
                    Spacer(minLength: 0)
                    Button("Next screen") { update { $0.screen(forward: true) } }
                }.font(.caption)
                if state.maximumOffset.x > 0 { panSlider("Across", horizontal: true) }
                if state.maximumOffset.y > 0 { panSlider("Down", horizontal: false) }
                DisclosureGroup("Read page text", isExpanded: $readText) {
                    ScrollView {
                        Text(picture.text()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.frame(maxHeight: 160)
                }
            case .failure(let error):
                Text("This page could not be displayed: \(String(describing: error))")
                    .textSelection(.enabled).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(index == 0 ? "Guide page" : "Comparison page")
    }

    private func update(_ action: (inout CDUserGuideRules.State) -> Void) { reader.update(index, action) }

    private func panSlider(_ title: String, horizontal: Bool) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 42, alignment: .leading)
            Slider(value: Binding(get: { Double(horizontal ? state.offset.x : state.offset.y) }, set: { value in
                update { $0.setOffset(x: horizontal ? Int(value) : $0.offset.x, y: horizontal ? $0.offset.y : Int(value)) }
            }), in: 0...Double(max(1, horizontal ? state.maximumOffset.x : state.maximumOffset.y)))
                .accessibilityLabel("Pan \(title.lowercased())")
        }
    }

    private func viewport(_ picture: CDGuideDocument.Picture) -> some View {
        VStack(spacing: 4) {
            Picker("Page tool", selection: $tool) {
                Text("Pan and links").tag(0)
                Text("Zoom in").tag(1)
                Text("Zoom out").tag(2)
            }.pickerStyle(.segmented)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(white: 0.75)
                    paper(picture)
                        .scaleEffect(CGFloat(state.zoomTenths) / 10, anchor: .topLeading)
                        .offset(x: -CGFloat(state.offset.x), y: -CGFloat(state.offset.y))
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                    guard tool == 0 else { return }
                    let start = dragStart ?? state.offset; dragStart = start
                    update { $0.setOffset(x: start.x - Int(value.translation.width), y: start.y - Int(value.translation.height)) }
                }.onEnded { _ in dragStart = nil })
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    guard tool != 0 else { return }
                    update { $0.magnify(at: .init(x: Int(value.location.x), y: Int(value.location.y)), increase: tool == 1) }
                })
                .onAppear { resize(geometry.size) }
                .onChange(of: geometry.size) { resize($0) }
            }.frame(minHeight: 100)
        }
    }
    private func resize(_ size: CGSize) { reader.resize(index, size: size) }

    private func paper(_ picture: CDGuideDocument.Picture) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if let background = try? document.picture(129) {
                Image(decorative: background.image, scale: 1).interpolation(.none).accessibilityHidden(true)
            }
            Image(decorative: picture.image, scale: 1).interpolation(.none)
                .offset(x: CGFloat(picture.paperOrigin.x)).accessibilityHidden(true)
            ForEach(Array((state.guide.links[state.pageID] ?? []).enumerated()), id: \.offset) { item in
                let link = item.element, rect = link.bounds
                Button { update { $0.activateLink(at: item.offset) } } label: {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: CGFloat(rect.right - rect.left), height: CGFloat(rect.bottom - rect.top))
                .accessibilityLabel(linkLabel(link, picture: picture, index: item.offset))
                .accessibilityHint(link.kind == .caption ? "Opens an explanation" : "Opens the linked page")
                .offset(x: CGFloat(rect.left), y: CGFloat(rect.top))
                .allowsHitTesting(tool == 0)
            }
        }.frame(width: 612, height: 792).clipped()
    }
    private func linkLabel(_ link: CDUserGuide.Link, picture: CDGuideDocument.Picture, index: Int) -> String {
        let title = picture.linkText(in: link.bounds).replacingOccurrences(of: "\n", with: " ")
        if !title.isEmpty { return title }
        if link.kind == .caption { return "Explanation \(index + 1)" }
        let page = (state.guide.pageIDs.firstIndex(of: link.destination) ?? 0) + 1
        return "Go to page \(page)"
    }
}
