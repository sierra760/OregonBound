import Foundation
import Testing
@testable import OregonBound

struct GameDataPreparationTests {
    @Test func malformedApplicationCannotReplaceAnInstalledPreparation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("prepared")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: destination.appendingPathComponent("sentinel"))
        var sources: [GameDataSourceRole: GameDataSourceCatalog.Candidate] = [:]
        for role in GameEdition.macintoshCD12.requiredRoles {
            let resources = GameSourceRequirements.resources(for: role).flatMap { type, ids in
                ids.map { MacResource(type: type, id: $0, name: nil, attributes: 0, data: Data([1])) }
            }
            let source = MacForkSource(displayName: role.rawValue, origin: role.rawValue, fileType: nil, creator: nil,
                                       dataFork: Data(), resourceFork: Data(role.rawValue.utf8))
            sources[role] = .init(source: source, fork: MacResourceFork(resources: resources))
        }
        let selection = GameDataSourceCatalog.Selection(edition: .macintoshCD12, sources: sources, unrecognized: [])
        #expect(throws: (any Error).self) {
            try GameDataPreparation.run(selection: selection, destination: destination, progress: { _ in })
        }
        let previous = try String(contentsOf: destination.appendingPathComponent("sentinel"), encoding: .utf8)
        #expect(previous == "previous")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["prepared"])
    }

    @Test func strictTextValidationRejectsTruncatedLists() {
        for (type, bytes): (String, [UInt8]) in [("STR#", [0, 1, 3, 97]), ("DITL", [0, 0]), ("HVof", [1])] {
            let fork = MacResourceFork(resources: [MacResource(type: type, id: 1, name: nil, attributes: 0, data: Data(bytes))])
            #expect(throws: (any Error).self) { try TextResourceExtractors.validate(fork) }
        }
    }

    static func styleScrap(_ starts: [UInt32], padding: UInt8 = 0) -> Data {
        var data = Data(); data.appendU16(UInt16(starts.count))
        for (index, start) in starts.enumerated() {
            data.appendU32(start)
            data.appendU16(15); data.appendU16(10); data.appendU16(21)
            data.append(UInt8(index % 2)); data.append(padding)
            data.appendU16(12)
            data.appendU16(0); data.appendU16(0); data.appendU16(0)
        }
        return data
    }

    @Test func styledCreditsPreserveMacRomanByteOffsetsAndCarriageReturns() throws {
        let text = Data([0x8e, 0x0d, 0x0d, 0x41, 0x20, 0x42, 0x0d])
        let parsed = try CDAboutCredits(text: text, styles: Self.styleScrap([0, 3], padding: 13))
        #expect(parsed.bytes == Array(text))
        #expect(parsed.text == "é\r\rA B\r")
        #expect(parsed.runs.map(\.start) == [0, 3])
        #expect(parsed.runs.map(\.face) == [0, 1])
        #expect(parsed.runs.allSatisfy { $0.height == 15 && $0.ascent == 10 && $0.font == 21 && $0.size == 12 })
        #expect(parsed.runs.allSatisfy { $0.red == 0 && $0.green == 0 && $0.blue == 0 })
        #expect(parsed == (try CDAboutCredits(text: text, styles: Self.styleScrap([0, 3]))))
    }

    @Test func styledCreditsRejectMalformedRunTablesAndExcessiveText() throws {
        let text = Data("Sample".utf8)
        for starts: [UInt32] in [[], [1], [0, 0], [0, 4, 3], [0, 6], [0, UInt32.max]] {
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: Self.styleScrap(starts)) }
        }
        let valid = Self.styleScrap([0])
        for length in 0..<valid.count {
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: valid.prefix(length)) }
        }
        #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: valid + Data([0])) }
        for (offset, value): (Int, UInt16) in [(6, 0), (6, 0xffff), (8, 16), (8, 0xffff), (10, 0xffff), (14, 0), (14, 0xffff)] {
            var malformed = valid
            malformed[offset] = UInt8(value >> 8); malformed[offset + 1] = UInt8(value & 255)
            #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: malformed) }
        }
        var face = valid; face[12] = 0x80
        #expect(throws: (any Error).self) { try CDAboutCredits(text: text, styles: face) }
        #expect(throws: (any Error).self) { try CDAboutCredits(text: Data(repeating: 65, count: 32768), styles: valid) }
        #expect(try CDAboutCredits(text: Data(repeating: 65, count: 32767), styles: valid).bytes.count == 32767)
        #expect(try CDAboutCredits(text: Data(), styles: Self.styleScrap([])).runs.isEmpty)
        #expect(throws: (any Error).self) { try CDAboutCredits(text: Data(), styles: valid) }
    }

    @Test func extractsValidatedCreditsFromPlayerResourcesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = Data("Team\rSample\r".utf8), styles = Self.styleScrap([0, 5])
        let fork = MacResourceFork(resources: [
            .init(type: "TEXT", id: 200, name: nil, attributes: 0, data: text),
            .init(type: "styl", id: 200, name: nil, attributes: 0, data: styles)])
        try CDAboutCredits.extract(from: fork, into: ExtractionOutput(root: root))
        #expect(try Data(contentsOf: root.appendingPathComponent("runtime/about_text_200.bin")) == text)
        #expect(try Data(contentsOf: root.appendingPathComponent("runtime/about_styl_200.bin")) == styles)
        #expect(throws: (any Error).self) {
            try CDAboutCredits.extract(from: MacResourceFork(resources: []), into: ExtractionOutput(root: root))
        }
    }

}
