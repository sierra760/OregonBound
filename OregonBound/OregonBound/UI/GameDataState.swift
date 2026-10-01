import Foundation
import Combine

enum GameDataLaunch {
    case legacy(URL)
    case prepared(PreparedGameSession)
}

@MainActor final class GameDataState: ObservableObject {
    typealias Importer = ([URL], @escaping (String) -> Void, @escaping () -> Bool) throws -> PreparedGameSession
    @Published private(set) var isReady: Bool
    @Published private(set) var sessionID = UUID()
    @Published private(set) var choices: [GameDataSelection] = []
    @Published var choice: GameDataSelection?
    @Published var selected: [URL] = []
    @Published private(set) var importing = false
    @Published var status = ""
    @Published var error: String?
    @Published var notes: [String] = []
    private let library: GameDataLibrary
    private let legacyRoot: URL?
    private let resetAudio: () -> Void
    private let activate: (GameDataLaunch) -> Void
    private let importer: Importer
    private var importTask: Task<Void, Never>?
    private var importID: UUID?

    init(library: GameDataLibrary = GameDataLibrary(),
         legacyRoot: URL? = GameData.preparedSession == nil ? GameData.root : nil,
         directLaunch: Bool = !(ProcessInfo.processInfo.environment[GameData.environmentOverride] ?? "").isEmpty,
         resetAudio: @escaping () -> Void = { GameAudio.shared.resetForSession() },
         activate: @escaping (GameDataLaunch) -> Void = { source in
             switch source { case .legacy(let root): GameData.activate(root); case .prepared(let session): GameData.activate(session) }
         }, importer: Importer? = nil) {
        self.library = library; self.legacyRoot = legacyRoot
        self.resetAudio = resetAudio; self.activate = activate
        self.importer = importer ?? { try library.importSources($0, progress: $1, isCancelled: $2) }
        isReady = directLaunch && legacyRoot != nil
        if !isReady { refreshChoices() }
    }

    func refreshChoices() {
        var available: [GameDataSelection] = legacyRoot == nil ? [] : [.legacyClassic]
        var failures: [String] = []
        for edition in GameEdition.allCases {
            do { if try library.load(edition) != nil { available.append(.installed(edition)) } }
            catch { failures.append("\(edition.title): \(error)") }
        }
        choices = available
        do {
            if choice == nil { choice = try library.selection() }
        } catch { failures.append("The last edition choice could not be read. \(error)") }
        if !available.contains(where: { $0 == choice }) { choice = available.first }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func play(_ selection: GameDataSelection) {
        guard !importing, !isReady, choices.contains(selection) else { return }
        do {
            let launch: GameDataLaunch
            switch selection {
            case .legacyClassic:
                guard let legacyRoot else { throw GameDataLibrary.Failure.invalid("missing classic import") }
                launch = .legacy(legacyRoot)
            case .installed(let edition):
                guard let session = try library.load(edition) else { throw GameDataLibrary.Failure.invalid("missing installed edition") }
                launch = .prepared(session)
            }
            try library.select(selection)
            resetAudio()
            activate(launch)
            choice = selection; error = nil
            sessionID = UUID()
            isReady = true
        } catch { self.error = "\(error)" }
    }

    /// Called only after the controller has stopped an inactive title session.
    func showLibrary() {
        guard !importing else { return }
        isReady = false
        error = nil
        refreshChoices()
    }
    func add(_ urls: [URL]) {
        guard !importing else { return }
        for url in urls where !selected.contains(url) { selected.append(url) }
        error = nil
    }
    func remove(_ url: URL) { if !importing { selected.removeAll { $0 == url } } }
    func cancelImport() { importTask?.cancel() }

    @discardableResult func startImport() -> Task<Void, Never>? {
        guard !isReady, !importing, !selected.isEmpty else { return nil }
        importing = true; error = nil; notes = []; status = "Starting…"
        let token = UUID()
        importID = token
        let sources = selected, importer = importer
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            let scoped = sources.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, granted) in scoped where granted { url.stopAccessingSecurityScopedResource() } }
            do {
                let session = try importer(sources, { message in
                    Task { @MainActor [weak self] in if self?.importID == token { self?.status = message } }
                }, { Task.isCancelled })
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.importing = false; self.importTask = nil; self.importID = nil
                    self.choice = .installed(session.edition)
                    self.refreshChoices()
                    self.notes = session.manifest.unrecognizedSources
                    self.status = "Imported \(session.edition.title)."
                    self.selected = []
                }
            } catch {
                let cancelled = Task.isCancelled
                await MainActor.run { [weak self] in
                    self?.error = cancelled ? nil : "\(error)"
                    self?.status = cancelled ? "Import cancelled." : ""
                    self?.importing = false; self?.importTask = nil; self?.importID = nil
                }
            }
        }
        return importTask
    }
}
