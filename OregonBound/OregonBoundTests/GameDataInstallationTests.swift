import Foundation
import Testing
@testable import OregonBound

struct GameDataInstallationTests {
    enum TestFailure: Error { case preparation, move }
    private func withDirectory(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("GameData")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: destination.appendingPathComponent("old.txt"))
        try body(root, destination)
    }
    private func oldContents(_ destination: URL) throws -> String {
        try String(contentsOf: destination.appendingPathComponent("old.txt"), encoding: .utf8)
    }

    @Test func preparationFailurePreservesInstalledFilesAndCleansStaging() throws {
        try withDirectory { (root: URL, destination: URL) throws -> Void in
            #expect(throws: TestFailure.self) {
                try GameDataInstallation.run(destination: destination) { staging in
                    try Data("partial".utf8).write(to: staging.appendingPathComponent("new.txt"))
                    throw TestFailure.preparation
                }
            }
            #expect(try oldContents(destination) == "old")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["GameData"])
        }
    }

    @Test func cancellationAfterPreparationPreservesInstalledFiles() throws {
        try withDirectory { (root: URL, destination: URL) throws -> Void in
            var cancelled = false
            #expect(throws: (any Error).self) {
                try GameDataInstallation.run(destination: destination, isCancelled: { cancelled }) { _ in
                    cancelled = true
                }
            }
            #expect(try oldContents(destination) == "old")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["GameData"])
        }
    }

    @Test func successfulReplacementInstallsOnlyPreparedFiles() throws {
        try withDirectory { (root: URL, destination: URL) throws -> Void in
            let value = try GameDataInstallation.run(destination: destination) { staging in
                try Data("new".utf8).write(to: staging.appendingPathComponent("new.txt"))
                return 42
            }
            #expect(value == 42)
            #expect(try String(contentsOf: destination.appendingPathComponent("new.txt"), encoding: .utf8) == "new")
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("old.txt").path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["GameData"])
        }
    }

    @Test func failedFinalMoveRestoresPreviousDirectory() throws {
        try withDirectory { (root: URL, destination: URL) throws -> Void in
            var moves = 0
            let move: (URL, URL) throws -> Void = { from, to in
                moves += 1
                if moves == 2 { throw TestFailure.move }
                try FileManager.default.moveItem(at: from, to: to)
            }
            #expect(throws: TestFailure.self) {
                try GameDataInstallation.run(destination: destination, move: move) { staging in
                    try Data("new".utf8).write(to: staging.appendingPathComponent("new.txt"))
                }
            }
            #expect(try oldContents(destination) == "old")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["GameData"])
        }
    }

    @Test func failedRollbackKeepsRecoverableBackup() throws {
        try withDirectory { (root: URL, destination: URL) throws -> Void in
            var moves = 0
            let move: (URL, URL) throws -> Void = { from, to in
                moves += 1
                if moves > 1 { throw TestFailure.move }
                try FileManager.default.moveItem(at: from, to: to)
            }
            var message = ""
            var preservedURL: URL?
            do {
                try GameDataInstallation.run(destination: destination, move: move) { _ in }
                Issue.record("Move failure was ignored")
            } catch {
                message = String(describing: error)
                if case GameDataInstallation.Failure.rollback(let backup, _, _) = error { preservedURL = backup }
            }
            let survivors = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            #expect(survivors.count == 1)
            let backup = try #require(survivors.first)
            #expect(try oldContents(backup) == "old")
            let reported = try #require(preservedURL)
            #expect(reported.resolvingSymlinksInPath() == backup.resolvingSymlinksInPath())
            #expect(message.contains(reported.path))
        }
    }

    @Test func nestedPreparationUsesIndependentStagingDirectories() throws {
        try withDirectory { (_: URL, destination: URL) throws -> Void in
            try GameDataInstallation.run(destination: destination) { outer in
                try Data("outer".utf8).write(to: outer.appendingPathComponent("outer.txt"))
                try GameDataInstallation.run(destination: destination) { inner in
                    #expect(inner != outer)
                    #expect(FileManager.default.fileExists(atPath: outer.appendingPathComponent("outer.txt").path))
                    try Data("inner".utf8).write(to: inner.appendingPathComponent("inner.txt"))
                }
                #expect(FileManager.default.fileExists(atPath: outer.appendingPathComponent("outer.txt").path))
            }
            #expect(try String(contentsOf: destination.appendingPathComponent("outer.txt"), encoding: .utf8) == "outer")
        }
    }
}
