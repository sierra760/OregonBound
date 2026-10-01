import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct GameDataSetupView: View {
    @ObservedObject var state: GameDataState
    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Oregon Bound").font(.title2.bold())
                if !state.choices.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose your game").font(.headline)
                        ForEach(state.choices) { choice in
                            Button { state.choice = choice } label: {
                                Label(choice.title, systemImage: state.choice == choice ? "largecircle.fill.circle" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).disabled(state.importing)
                                .accessibilityAddTraits(state.choice == choice ? [.isSelected] : [])
                        }
                        if state.choice == .installed(.macintoshCD12) {
                            Picker("Artwork", selection: $state.colorMode) {
                                ForEach(PreparedGameSession.ColorMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }.pickerStyle(.segmented).disabled(state.importing)
                            Text("Choose the CD edition’s original color artwork.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Button("Play") { if let choice = state.choice { state.play(choice) } }
                            .keyboardShortcut(.defaultAction).disabled(state.importing || state.choice == nil)
                    }
                    Divider()
                    Text("Add or replace game data").font(.headline)
                }
                Text("""
                Supply your own Macintosh “The Oregon Trail” (color version 1.1) or “Oregon Trail CD” (version 1.2) files. \
                The original graphics, text, fonts and sounds are copyrighted and are not included. \
                Everything is decoded on this device and kept in the app’s support folder.
                """)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Classic: the “Oregon Trail” application and “Oregon Color” file", systemImage: "1.circle")
                    Label("CD: the “Oregon Trail CD” application and its “Oregon Data” folder", systemImage: "2.circle")
                    Text("Add the game folder, a disk image (.dsk, .img, .image, Disk Copy 4.2), MacBinary (.bin), BinHex (.hqx), AppleDouble or raw resource-fork (.rsrc) files. Expand StuffIt (.sit) archives first.")
                        .font(.callout).foregroundStyle(.secondary).padding(.leading, 28)
                    Label("Recommended: a System 7.0 disk image", systemImage: "3.circle")
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
                        .disabled(state.importing || state.selected.isEmpty)
                    if state.importing { Button("Cancel", action: state.cancelImport) }
                    if state.importing { ProgressView().controlSize(.small) }
                    Text(state.status).foregroundStyle(.secondary).lineLimit(1)
                }
                if let error = state.error {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                if !state.notes.isEmpty {
                    Text("Files outside the supported game data: \(state.notes.joined(separator: ", "))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24).frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): state.add(urls)
            case .failure(let error): state.error = error.localizedDescription
            }
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
