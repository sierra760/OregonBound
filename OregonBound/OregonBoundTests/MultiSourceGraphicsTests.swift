import Foundation
import Testing
@testable import OregonBound

struct MultiSourceGraphicsTests {
    private func bitmap() -> Data {
        var data = Data()
        data.appendU16(1)
        data.appendU32(20)
        data.appendU32(0)
        for value: UInt16 in [1, 3, 5, 4, 6] { data.appendU16(value) }
        data.append(contentsOf: [1, 0x80])
        return data
    }
    private func resource(_ type: String, _ id: Int, _ payload: Data) -> MacResource {
        MacResource(type: type, id: id, name: "Synthetic", attributes: 0, data: payload)
    }
    private func withOutput(_ body: (ExtractionOutput) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(ExtractionOutput(root: root))
    }

    @Test func oversizedColorBackingStoreIsRejectedBeforeCropping() {
        var pixmap = Data(repeating: 0, count: 50)
        pixmap.replaceSubrange(4..<6, with: [0xbe, 0x80]) // 16000-byte stride
        pixmap.replaceSubrange(10..<14, with: [0x10, 0x68, 0, 1]) // 4200 rows, 1 pixel
        pixmap.replaceSubrange(32..<34, with: [0, 8])
        pixmap.replaceSubrange(42..<46, with: [255, 255, 255, 255])
        var data = Data()
        data.appendU16(1)
        data.appendU32(59)
        data.append(pixmap)
        data.append(Data(repeating: 0, count: 5))
        let info = ResourceInfo(sourceFile: "synthetic", resourceType: "Imag", resourceId: 7,
                                name: "", rawLength: data.count)
        let records = ImagDecoder.decode(resource: info, data: data,
                                         fallbackPalette: Array(repeating: 0, count: 768), fallbackSource: "synthetic")
        #expect(records[0].status == .failed)
        #expect(records[0].image == nil)
        #expect(records[0].diagnostics.contains { $0.message.contains("backing store") })
    }

    @Test(arguments: [UInt8(0xE8), 0xE9, 0xEF, 0x89, 0x8F, 0x09, 0x0F, 0x49, 0x4F])
    func truncatedCompressedColorRowsFailStrictImport(opcode: UInt8) throws {
        var pixmap = Data(repeating: 0, count: 50)
        pixmap.replaceSubrange(4..<6, with: [0x80, 3])
        pixmap.replaceSubrange(10..<14, with: [0, 1, 0, 3])
        pixmap.replaceSubrange(32..<34, with: [0, 8])
        pixmap.replaceSubrange(42..<46, with: [255, 255, 255, 255])
        var stream = Data([3, 0, 1, 0, 1, opcode])
        if opcode < 0x80 { stream.append(contentsOf: [3, 0]) }
        var data = Data()
        data.appendU16(1)
        data.appendU32(UInt32(54 + stream.count))
        data.append(pixmap)
        data.append(stream)
        try withOutput { output in
            let fork = MacResourceFork(resources: [resource("Imag", 7, data)])
            #expect(throws: (any Error).self) {
                try GraphicsExtractor.extract(colorFork: fork, into: output, expectedCounts: [], strict: true)
            }
            #expect(!FileManager.default.fileExists(atPath: output.url("graphics_manifest.json").path))
        }
    }

    @Test func ima4AndImagKeepDistinctPathsAndBounds() throws {
        try withOutput { output in
            let fork = MacResourceFork(resources: [resource("Imag", 7, bitmap()), resource("Ima4", 7, bitmap())])
            let manifest = try GraphicsExtractor.extract(colorFork: fork, into: output, sourceName: "graphics3", expectedCounts: [], strict: true)
            #expect(manifest.images.count == 2)
            #expect(Set(manifest.images.compactMap(\.imagePath)).count == 2)
            #expect(manifest.images.allSatisfy { $0.resource.sourceFile == "graphics3" && $0.bounds == [3, 5, 4, 6] })
            #expect(FileManager.default.fileExists(atPath: output.url("images/Ima4/ima4_7.png").path))
        }
    }

    @Test func failedFramesAbortStrictExtraction() throws {
        try withOutput { output in
            let fork = MacResourceFork(resources: [resource("Imag", 7, Data([0, 1, 0]))])
            #expect(throws: (any Error).self) {
                try GraphicsExtractor.extract(colorFork: fork, into: output, sourceName: "graphics1", expectedCounts: [], strict: true)
            }
            #expect(!FileManager.default.fileExists(atPath: output.url("graphics_manifest.json").path))
        }
    }

    @Test func explicitlyCatalogedPlaceholderDoesNotProduceAFailedImage() throws {
        try withOutput { output in
            let fork = MacResourceFork(resources: [resource("Imag", 15522, Data([0, 0])), resource("Imag", 7, bitmap())])
            let manifest = try GraphicsExtractor.extract(colorFork: fork, into: output, sourceName: "graphics1", expectedCounts: [],
                                                         emptyPlaceholders: [.init(type: "Imag", id: 15522)], strict: true)
            #expect(manifest.images.count == 1)
            #expect(manifest.images[0].resource.resourceId == 7)
        }
    }
}
