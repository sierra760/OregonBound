import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Tracks the imported data and drives the one-time import from the player's files.
@MainActor final class GameDataState: ObservableObject {
    @Published var isReady = GameData.isReady
    @Published var selected: [URL] = []
    @Published var importing = false
    @Published var status = ""
    @Published var error: String?
    @Published var notes: [String] = []

    func add(_ urls: [URL]) {
        for url in urls where !selected.contains(url) { selected.append(url) }
        error = nil
    }
    func remove(_ url: URL) { selected.removeAll { $0 == url } }

    func startImport() {
        guard !importing, !selected.isEmpty else { return }
        importing = true; error = nil; notes = []; status = "Starting…"
        let sources = selected
        Task.detached(priority: .userInitiated) { [weak self] in
            let scoped = sources.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, granted) in scoped where granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let report = try GameDataImporter.run(sources: sources) { message in
                    Task { @MainActor [weak self] in self?.status = message }
                }
                await MainActor.run { [weak self] in
                    GameData.activate(report.root)
                    self?.notes = report.notes
                    self?.importing = false
                    self?.isReady = true
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.error = "\(error)"
                    self?.status = ""
                    self?.importing = false
                }
            }
        }
    }
}

struct GameDataSetupView: View {
    @ObservedObject var state: GameDataState
    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Oregon Bound").font(.title2.bold())
                Text("""
                This recreation plays with the graphics, text, fonts and sounds of MECC’s 1991 Macintosh “The Oregon Trail” \
                (color version 1.1). Those files are copyrighted and are not included, so you need to supply your own copy. \
                Everything is decoded on this device and kept in the app’s support folder.
                """)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Required: the “Oregon Trail” application and the “Oregon Color” file", systemImage: "1.circle")
                    Text("Add the game folder, a disk image (.dsk, .img, .image, Disk Copy 4.2), MacBinary (.bin), BinHex (.hqx), AppleDouble or raw resource-fork (.rsrc) files. Expand StuffIt (.sit) archives first.")
                        .font(.callout).foregroundStyle(.secondary).padding(.leading, 28)
                    Label("Recommended: a System 7.0 disk image", systemImage: "2.circle")
                    Text("The original Chicago and Geneva screen fonts, alert icons and scroll bars come from the System 7.0 “System” file. Without it the game still runs, with substitutes for those parts.")
                        .font(.callout).foregroundStyle(.secondary).padding(.leading, 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.selected, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button { state.remove(url) } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless).disabled(state.importing)
                        }
                    }
                    if state.selected.isEmpty { Text("Nothing added yet.").foregroundStyle(.secondary) }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                HStack {
                    Button("Add Files or Folders…") { choose() }.disabled(state.importing)
                    Button("Import") { state.startImport() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(state.importing || state.selected.isEmpty)
                    if state.importing { ProgressView().controlSize(.small) }
                    Text(state.status).foregroundStyle(.secondary).lineLimit(1)
                }
                if let error = state.error {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24).frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { state.add(urls) }
        }
        #endif
    }

    private func choose() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.message = "Choose the original Oregon Trail files, a disk image, or a folder containing them"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = true
        panel.begin { response in
            guard response == .OK else { return }
            state.add(panel.urls)
        }
        #else
        showingPicker = true
        #endif
    }
}
