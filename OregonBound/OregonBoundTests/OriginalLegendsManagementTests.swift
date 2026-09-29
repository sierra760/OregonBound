import Foundation
import Testing
@testable import OregonBound

struct OriginalLegendsManagementTests {
    @Test func removeIsLocalUntilDoneAndOriginalKeepsPendingDeletion() {
        var editor = OriginalLegendsManagement.Editor(legends: OriginalEndingPresentation.initialLegends)
        editor.select(0); editor.select(2, extending: true)
        editor.removeSelected()
        #expect(editor.rows.count == 8 && editor.pendingRemovals.count == 2)
        editor.restored(OriginalEndingPresentation.initialLegends)
        #expect(editor.rows.count == 10 && editor.pendingRemovals.count == 2)
        #expect(editor.selected.isEmpty)
    }
    @Test func selectAllClearsAndNoSelectionDoesNothing() {
        var editor = OriginalLegendsManagement.Editor(legends: OriginalEndingPresentation.initialLegends)
        editor.removeSelected()
        #expect(editor.rows.count == 10)
        editor.selectAll(); editor.removeSelected()
        #expect(editor.rows.isEmpty && editor.pendingRemovals.count == 10)
    }
    @Test func clearedTableSurvivesReopenAndNewScoreDoesNotRestoreDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyStore(directory: directory)
        #expect(try store.legends().count == 10)
        try store.removeLegends(store.legends())
        let reopened = JourneyStore(directory: directory)
        #expect(try reopened.legends().isEmpty)
        var trip = Journey(seed: 1)
        JourneyEngine.finish(&trip, won: true, reason: "Arrived")
        try reopened.recordScore(trip, name: "New traveler")
        #expect(try reopened.legends().map(\.name) == ["New traveler"])
        try reopened.restoreOriginalLegends()
        #expect(try reopened.legends() == OriginalEndingPresentation.initialLegends)
        #expect(try reopened.scores().isEmpty)
    }
    @Test func queuedDeletionStillMatchesRestoredRowsByNameAndScore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyStore(directory: directory)
        let removal = OriginalEndingPresentation.Legend(id: "different-id", name: "Stephen Meek", score: 7650)
        try store.restoreOriginalLegends()
        try store.removeLegends([removal])
        #expect(try store.legends().count == 9)
        #expect(try store.legends().first?.name == "David Hastings")
    }
    @Test func legacyArrayMigratesAndMalformedTableThrows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("hall-of-fame.json")
        try Data("[]".utf8).write(to: url)
        let store = JourneyStore(directory: directory)
        #expect(try store.legends() == OriginalEndingPresentation.initialLegends)
        try Data("{\"format\":\"OregonBoundLegends\",\"version\":99,\"players\":[],\"legends\":[]}".utf8).write(to: url)
        #expect(throws: Error.self) { try store.legends() }
    }
}
