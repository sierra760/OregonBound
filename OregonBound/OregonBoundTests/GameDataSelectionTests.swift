import Foundation
import Testing
@testable import OregonBound

struct GameDataSelectionTests {
    @MainActor @Test(arguments: PreparedGameSession.ColorMode.allCases)
    func colorChoiceIsCapturedAtPlayAndClassicStaysUnchanged(mode: PreparedGameSession.ColorMode) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        for edition in GameEdition.allCases {
            _ = try library.install(edition: edition) { _ = try PreparedSessionFixture.make(at: $0, edition: edition, schemaVersion: 9, icons: true) }
        }
        var launched: PreparedGameSession?
        let state = GameDataState(library: library, legacyRoot: nil, directLaunch: false,
            resetAudio: {}, activate: { if case .prepared(let session) = $0 { launched = session } })
        state.colorMode = mode
        state.play(.installed(.macintoshCD12))
        #expect(launched?.colorMode == mode)
        state.colorMode = mode == .color256 ? .monochrome : .color256
        #expect(launched?.colorMode == mode)
        state.showLibrary(); state.colorMode = .monochrome
        state.play(.installed(.macintosh11))
        #expect(launched?.colorMode == .color256)
    }
    @MainActor @Test func olderCDImportOffersReimportAndReplacedGenerationBecomesPlayable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        let session = try library.install(edition: .macintoshCD12) { _ = try PreparedSessionFixture.make(at: $0) }
        let manifestURL = session.root.appendingPathComponent("prepared_import.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["schemaVersion"] = 8
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        var launched: PreparedGameSession?
        let state = GameDataState(library: library, legacyRoot: nil, directLaunch: false,
            resetAudio: {}, activate: { if case .prepared(let session) = $0 { launched = session } })
        for mode in PreparedGameSession.ColorMode.allCases {
            state.colorMode = mode
            state.play(.installed(.macintoshCD12))
            #expect(launched == nil && !state.isReady)
            #expect(state.error?.contains("Re-import") == true)
            #expect(!state.choices.contains(.installed(.macintoshCD12)))
        }
        _ = try library.install(edition: .macintoshCD12) { _ = try PreparedSessionFixture.make(at: $0) }
        state.refreshChoices()
        state.colorMode = .color256
        state.play(.installed(.macintoshCD12))
        #expect(launched?.colorMode == .color256 && state.isReady && state.error == nil)
    }

    @Test func remembersChoiceWithoutChangingCurrentGenerations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        #expect(try library.selection() == nil)
        for choice in [GameDataSelection.installed(.macintoshCD12), .installed(.macintosh11), .legacyClassic] {
            try library.select(choice)
            #expect(try GameDataLibrary(root: root).selection() == choice)
        }
        #expect(try library.load(.macintoshCD12) == nil)
    }
    @Test(arguments: ["version", "edition", "legacy"])
    func rejectsInvalidSelection(kind: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var value: [String: Any] = ["schemaVersion": 1, "source": "installed", "edition": GameEdition.macintoshCD12.rawValue]
        switch kind {
        case "version": value["schemaVersion"] = 9
        case "edition": value["edition"] = "future"
        default: value["source"] = "legacy"
        }
        try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("selection.json"))
        #expect(throws: (any Error).self) { try GameDataLibrary(root: root).selection() }
    }
    @MainActor @Test func selectionAdoptsOnlyOnPlayAndRetainsLegacyChoice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        _ = try library.install(edition: .macintoshCD12) { _ = try PreparedSessionFixture.make(at: $0) }
        let legacy = root.appendingPathComponent("legacy")
        var trace: [String] = []
        let state = GameDataState(library: library, legacyRoot: legacy, directLaunch: false,
            resetAudio: { trace.append("reset") }, activate: { data in
                switch data { case .legacy: trace.append("legacy"); case .prepared(let session): trace.append(session.edition.rawValue) }
            })
        #expect(!state.isReady && trace.isEmpty)
        #expect(state.choices.contains(.legacyClassic) && state.choices.contains(.installed(.macintoshCD12)))
        state.play(.installed(.macintoshCD12))
        #expect(state.isReady)
        #expect(trace == ["reset", GameEdition.macintoshCD12.rawValue])
        #expect(try library.selection() == .installed(.macintoshCD12))
        let firstID = state.sessionID
        state.showLibrary()
        state.play(.legacyClassic)
        #expect(state.sessionID != firstID)
        #expect(trace.suffix(2) == ["reset", "legacy"])
    }
    @MainActor @Test func controllerOnlyLeavesInactiveTitleScreen() {
        let game = GameController(store: JourneyStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        var requested = 0
        game.chooseGameData = { requested += 1 }
        game.creatingGame = true; game.requestGameData(); #expect(requested == 0)
        game.creatingGame = false; game.showingAbout = true; game.requestGameData(); #expect(requested == 0)
        game.showingAbout = false; game.trip = Journey(seed: 1); game.requestGameData(); #expect(requested == 0)
        game.trip = nil; game.requestGameData(); #expect(requested == 1)
        #expect(!game.applicationActive)
    }
    @MainActor @Test func importAddsChoiceWithoutActivatingAndRemembersPlayedChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        var activated = false
        let state = GameDataState(library: library, legacyRoot: nil, directLaunch: false,
            resetAudio: {}, activate: { _ in activated = true }, importer: { _, _, _ in
                try library.install(edition: .macintoshCD12) { _ = try PreparedSessionFixture.make(at: $0) }
            })
        state.add([root.appendingPathComponent("synthetic-source")])
        let task = try #require(state.startImport())
        #expect(state.importing)
        #expect(state.startImport() == nil)
        await task.value
        #expect(!state.importing && !state.isReady && !activated)
        #expect(state.choice == .installed(.macintoshCD12))
        #expect(try library.selection() == nil)
        state.play(.installed(.macintoshCD12))
        #expect(activated && state.isReady)
        let restarted = GameDataState(library: library, legacyRoot: nil, directLaunch: false, resetAudio: {}, activate: { _ in })
        #expect(restarted.choice == .installed(.macintoshCD12) && !restarted.isReady)
    }
    @MainActor @Test(arguments: [false, true])
    func failedOrCancelledImportLeavesChoiceUsable(cancel: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let release = DispatchSemaphore(value: 0)
        let state = GameDataState(library: GameDataLibrary(root: root), legacyRoot: root, directLaunch: false,
            resetAudio: {}, activate: { _ in }, importer: { _, _, isCancelled in
                _ = release.wait(timeout: .now() + 5)
                if isCancelled() { throw GameDataInstallation.Failure.cancelled }
                throw GameDataLibrary.Failure.invalid("synthetic failure")
            })
        state.add([root.appendingPathComponent("synthetic-source")])
        let task = try #require(state.startImport())
        if cancel { state.cancelImport() }
        release.signal()
        await task.value
        #expect(!state.importing && !state.isReady)
        #expect(state.choices == [.legacyClassic])
        #expect((state.error == nil) == cancel)
        state.play(.legacyClassic)
        #expect(state.isReady)
    }
    @MainActor @Test func invalidReloadDoesNotActivateOrReplaceChoice() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = GameDataLibrary(root: root)
        let session = try library.install(edition: .macintoshCD12) { _ = try PreparedSessionFixture.make(at: $0) }
        try library.select(.legacyClassic)
        var activated = false
        let state = GameDataState(library: library, legacyRoot: root, directLaunch: false, resetAudio: {}, activate: { _ in activated = true })
        try FileManager.default.removeItem(at: session.root.appendingPathComponent("prepared_import.json"))
        state.play(.installed(.macintoshCD12))
        #expect(!state.isReady && !activated && state.error != nil)
        #expect(try library.selection() == .legacyClassic)
    }
}
