import Foundation
import Testing
@testable import OregonBound

struct BitmapImagTests {
    private let commands: [UInt8] = [2, 0x80, 0, 0xFE, 0xFF, 0xBE, 0, 0x80]
    private var expected: [UInt8] {
        [0] + Array(repeating: 255, count: 8) + Array(repeating: 255, count: 8) + [0]
            + Array(repeating: 0, count: 8) + [255] + Array(repeating: 0, count: 9)
    }

    private func frame(_ payload: [UInt8]? = nil, width: UInt16 = 9,
                       height: UInt16 = 4, stride: UInt16 = 2) -> Data {
        let payload = payload ?? commands
        var data = Data()
        data.appendU32(UInt32(18 + payload.count))
        data.appendU32(0)
        for value: UInt16 in [stride, 0, 0, height, width] { data.appendU16(value) }
        data.append(contentsOf: payload)
        return data
    }

    private func decode(_ frames: [Data], count: UInt16? = nil) -> [DecodedImage] {
        var data = Data()
        data.appendU16(count ?? UInt16(frames.count))
        for frame in frames { data.append(frame) }
        let info = ResourceInfo(sourceFile: "synthetic", resourceType: "Imag", resourceId: 123,
                                name: "Columns", rawLength: data.count)
        return ImagDecoder.decode(resource: info, data: data,
                                  fallbackPalette: Array(repeating: 0, count: 768), fallbackSource: "synthetic")
    }

    @Test func columnCommandsAndCrop() throws {
        let records = decode([frame()])
        #expect(records.count == 1)
        let result = try #require(records.first)
        #expect(result.status == .ok)
        #expect(result.width == 9 && result.height == 4 && result.mode == "L")
        #expect(result.image?.pixels == expected)
        #expect(result.palette == nil)
        #expect(result.byteRanges["pixels"] == [20, 28])
        #expect(result.frameIndex == 0 && result.frameCount == 1)
    }

    @Test func declaredBoundariesAndZeroControl() {
        let records = decode([frame(commands + [0]), frame([0] + commands)])
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.status == .ok && $0.image?.pixels == expected })
        #expect(records.map { $0.byteRanges["pixels"] } == [[20, 28], [47, 56]])
    }

    @Test func malformedCommandsAndDimensions() {
        let badCommands: [[UInt8]] = [[], [2, 0x80], [0xBE, 0], [0xFC], [5, 0, 0, 0, 0, 0], [0xBB, 0, 0x80], [0]]
        for payload in badCommands {
            #expect(decode([frame(payload)])[0].status == .failed)
        }
        for (width, height, stride): (UInt16, UInt16, UInt16) in
            [(17, 4, 2), (0, 4, 2), (9, 0, 2), (9, 4, 0), (32760, 32760, 4096)] {
            #expect(decode([frame(width: width, height: height, stride: stride)])[0].status == .failed)
        }
        #expect(decode([frame([2, 0x80]), frame()])[0].status == .failed)
        for length: UInt32 in [0, 17, 27, .max] {
            var payload = Data()
            payload.appendU32(length)
            payload.append(frame().dropFirst(4))
            #expect(decode([payload])[0].status == .failed)
        }
    }

    @Test func partialResourceReportsShortfall() {
        let records = decode([frame()], count: 2)
        #expect(records.count == 1)
        #expect(records[0].status == .partial)
        #expect(records[0].image?.pixels == expected)
        #expect(records[0].diagnostics.contains { $0.code == "imag.decoded_frame_shortfall" })
    }
}
