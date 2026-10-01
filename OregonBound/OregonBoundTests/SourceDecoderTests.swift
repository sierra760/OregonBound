import Foundation
import Testing
@testable import OregonBound

struct SourceDecoderTests {
    private func table(_ entries: [[UInt8]]) -> Data {
        var result = Data()
        result.appendU16(UInt16(entries.count))
        for entry in entries {
            if result.count % 2 != 0 { result.append(0) }
            result.appendU16(UInt16(entry.count))
            result.append(contentsOf: entry)
        }
        return result
    }

    @Test func guideUsesLengthsAndPreservesEmptySlots() throws {
        let entries: [[UInt8]] = [Array("abc".utf8), [], [111, 110, 101, 1, 116, 119, 111, 0],
                                 Array(repeating: 97, count: 255), Array(repeating: 98, count: 256),
                                 Array(repeating: 99, count: 512), Array("z".utf8)]
        let parsed = try TextResourceExtractors.parseWST(table(entries), resourceID: 12, name: "Synthetic")
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(parsed)) as? [String: Any])
        #expect(object["entry_count"] as? Int == 7)
        let output = try #require(object["entries"] as? [[String: Any]])
        #expect(output.count == 7)
        for (index, entry) in output.enumerated() {
            #expect(entry["index"] as? Int == index)
            #expect(entry["text"] as? String == String(data: Data(entries[index]), encoding: .macOSRoman))
        }
    }

    @Test func guideRejectsTruncatedFields() {
        let cases: [[UInt8]] = [[], [0], [0, 1], [0, 1, 0], [0, 1, 0, 3, 97, 98],
                               [0, 2, 0, 1, 97, 0, 0]]
        for bytes in cases {
            #expect(throws: (any Error).self) {
                _ = try TextResourceExtractors.parseWST(Data(bytes), resourceID: 12, name: nil)
            }
        }
    }

    private func sound(_ command: UInt16) -> Data {
        var result = Data()
        for value: UInt16 in [1, 0, 1, command, 0] { result.appendU16(value) }
        result.appendU32(14)
        for value: UInt32 in [0, 3, 22050 << 16, 0, 3] { result.appendU32(value) }
        result.append(contentsOf: [0, 60, 0, 128, 255])
        return result
    }

    @Test func soundAcceptsBothOffsetCommandForms() throws {
        for command: UInt16 in [0x8050, 0x8051] {
            let decoded = try SoundExtractor.parseFormat1(sound(command))
            #expect(decoded.sampleRate == 22050)
            #expect(decoded.bitsPerSample == 8)
            #expect(decoded.pcm == Data([0, 128, 255]))
            #expect(!decoded.truncated)
        }
    }

    @Test func soundRejectsPointerCommands() {
        for command: UInt16 in [0x0050, 0x0051] {
            #expect(throws: (any Error).self) { try SoundExtractor.parseFormat1(sound(command)) }
        }
    }

    @Test func soundRejectsTruncatedTablesAndBadOffsets() {
        var badOffset = sound(0x8051)
        badOffset.replaceSubrange(10..<14, with: [255, 255, 255, 255])
        let cases = [Data([0, 1, 0, 2, 0, 0]), Data([0, 1, 0, 0, 0, 1]), badOffset]
        for bytes in cases {
            #expect(throws: (any Error).self) { try SoundExtractor.parseFormat1(bytes) }
        }
    }

    @Test func strictSoundRejectsTruncationPointersAndInvalidHeaders() {
        var pointer = sound(0x8051)
        pointer.replaceSubrange(14..<18, with: [0, 0, 0, 123])
        var zeroRate = sound(0x8051)
        zeroRate.replaceSubrange(22..<26, with: [0, 0, 0, 0])
        var overlapping = sound(0x8051)
        overlapping.replaceSubrange(10..<14, with: [0, 0, 0, 0])
        for bytes in [pointer, zeroRate, overlapping, Data(sound(0x8051).dropLast())] {
            #expect(throws: (any Error).self) { try SoundExtractor.parseFormat1(bytes, strict: true) }
        }
    }

    @Test func cdOriginIsACheckedPascalStringWithExplicitType() throws {
        let result = try TextResourceExtractors.parseOTCD(Data([3, 97, 98, 99]), resourceID: 0, sourceFile: "cd")
        #expect(result == ["id": 0, "text": "abc", "source_file": "cd", "source_type": "OTCD"])
        #expect(throws: (any Error).self) {
            try TextResourceExtractors.parseOTCD(Data([4, 97, 98, 99]), resourceID: 0, sourceFile: "cd")
        }
    }

}
