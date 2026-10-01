import Foundation
import Testing
@testable import OregonBound

struct CDDisplayTests {
    private func initializer(_ stream: [UInt8], size: UInt32 = 0x2400) -> Data {
        var data = Data([0x48,0xe7,0x7f,0xf8,0x49,0xfa,0,26])
        data += Data(repeating: 0, count: 24)
        data.appendU32(size); data.appendU16(1); data.appendU16(0)
        data.appendU32(16); data.appendU32(UInt32(16 + stream.count))
        data += Data(stream)
        return data
    }
    private func table() -> Data {
        var data = Data(); data.appendU32(0); data.appendU16(0x8000); data.appendU16(15)
        for i in 0..<16 {
            data.appendU16(0x8000); data.appendU16(UInt16(i * 0x1100))
            data.appendU16(UInt16((15-i) * 0x1100)); data.appendU16(0)
        }
        return data
    }
    private func code() -> Data {
        initializer([0,0x81,0,0x80,0xee] + (0..<256).map { UInt8($0 % 16) } + [0,0])
    }
    @Test(arguments: [[UInt8(2)], [0x80,2], [0xc0,0,2], [0xe0,0,0,0,2]])
    func initializerNumberWidths(number: [UInt8]) throws {
        let memory = try CD16Palette.initializedBytes(initializer([0] + number + [0,97,98,0,0], size: 8))
        #expect(memory == [97,98,0,0,0,0,0,0])
    }
    @Test func repetitionsConsumeDistinctLiteralsAndRepeatSkip() throws {
        #expect(try CD16Palette.initializedBytes(initializer([0,0xf0,2,3,1,97,98,99,100,101,102,0,0], size: 10))
                == [0,97,98,0,99,100,0,101,102,0])
        #expect(try CD16Palette.initializedBytes(initializer([0x11,97,98,0,0], size: 5)) == [0,0,97,98,0])
    }
    @Test func nestedRepeatNumberPreservesRegisterExchange() throws {
        let literals = Array("abcdefghijkl".utf8)
        let stream: [UInt8] = [0,0xf0,2,0xf0,3,4,0] + literals + [0,0]
        #expect(try CD16Palette.initializedBytes(initializer(stream, size: 12)) == literals)
    }
    @Test(arguments: [[], [UInt8(0)], [0,2,0,97], [0,2,8,97,98,0,0], [0,0xf0,2,0,0,97,98,0,0],
                      [0,0xf0,2,127,0,97,98,0,0], [0] + Array(repeating: 0xf0, count: 10), [0,0,99]])
    func invalidInitializerStreams(stream: [UInt8]) {
        #expect(throws: (any Error).self) { try CD16Palette.initializedBytes(initializer(stream, size: 8)) }
    }
    @Test func authoredIndicesPreserveOddWidthAndProvenance() throws {
        let palette = try CD16Palette(initializer: Data([0,32,0,1]) + code(), colorTable: table())
        let info = ResourceInfo(sourceFile: "synthetic", resourceType: "Ima4", resourceId: 7, name: "", rawLength: 99)
        let input = DecodedImage(resource: info, status: .partial, imagePath: nil, width: 3, height: 2, mode: "P",
            byteRanges: ["pixels": [2,99]], diagnostics: [.init("warning", "imag.palette_fallback", "unused")],
            image: .init(width: 3, height: 2, colorType: .indexed, pixels: [0,17,255,34,3,132]), bounds: [4,5,6,8])
        let output = try palette.convert(input)
        #expect(output.image?.pixels == [0,1,15,2,3,4])
        let expectedColors: [UInt8] = (0..<16).flatMap { [UInt8($0*17), UInt8((15-$0)*17), UInt8(0)] }
        #expect(output.image?.palette.prefix(48) == expectedColors[...])
        #expect(output.status == .ok && output.diagnostics.isEmpty)
        #expect(output.bounds == [4,5,6,8] && output.byteRanges == ["pixels": [2,99]])
        #expect(output.resource == info && output.palette?.entryCount == 16)
    }
    @Test func extractorConvertsOnlyAlternateArtwork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var pixmap = Data(repeating: 0, count: 50)
        pixmap.replaceSubrange(4..<14, with: [0x80,4,0,4,0,5,0,6,0,8])
        pixmap.replaceSubrange(32..<34, with: [0,8])
        pixmap.replaceSubrange(42..<46, with: [255,255,255,255])
        let stream = Data([4,0,2,0,1,0xc0,0,17,255,7,0xc0,34,3,132,7])
        var payload = Data(); payload.appendU16(1); payload.appendU32(UInt32(54 + stream.count))
        payload += pixmap + stream
        let fork = MacResourceFork(resources: ["Imag", "Ima4"].map {
            MacResource(type: $0, id: 7, name: "Synthetic", attributes: 0, data: payload)
        })
        let manifest = try GraphicsExtractor.extract(colorFork: fork, into: ExtractionOutput(root: root),
            expectedCounts: [], strict: true, cd16Palette: CD16Palette(initializer: Data([0,32,0,1]) + code(), colorTable: table()))
        let alternate = try #require(manifest.images.first { $0.resource.resourceType == "Ima4" })
        let regular = try #require(manifest.images.first { $0.resource.resourceType == "Imag" })
        #expect(alternate.image?.pixels == [0,1,15,2,3,4])
        #expect(regular.image?.pixels == [0,17,255,34,3,132])
        #expect(alternate.bounds == [4,5,6,8] && alternate.palette?.source == "cd_16_color")
        let alternatePath = try #require(alternate.imagePath), regularPath = try #require(regular.imagePath)
        #expect(try Data(contentsOf: root.appendingPathComponent(alternatePath)) !=
                    Data(contentsOf: root.appendingPathComponent(regularPath)))
    }
    @Test(arguments: ["size", "version", "flags", "header", "start", "end", "map", "palette"])
    func invalidSources(kind: String) {
        var data = code(); var colors = table()
        switch kind {
        case "size": data.replaceSubrange(32..<36, with: [255,255,255,255])
        case "version": data[37] = 2
        case "flags": data[39] = 1
        case "header": data[4] = 0
        case "start": data[43] = 15
        case "end": data.replaceSubrange(44..<48, with: [255,255,255,255])
        case "map": data[53] = 16
        default: colors.removeLast()
        }
        #expect(throws: (any Error).self) { try CD16Palette(initializer: Data([0,32,0,1]) + data, colorTable: colors) }
    }
}
