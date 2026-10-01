import Foundation
import Testing
@testable import OregonBound

struct RasterPICTTests {
    private func words(_ values: [UInt16]) -> Data {
        var data = Data()
        for value in values { data.appendU16(value) }
        return data
    }
    @Test func monochromeCropsRelativeToBounds() throws {
        let frame = words([3, 5, 4, 7])
        let region = words([10]) + frame
        var data = words([0]) + frame + Data([0x11, 1, 1]) + region + Data([0x99])
        data += words([8, 3, 0, 4, 64]) + frame + frame + words([0]) + region
        data += Data([4, 0, 4, 250, 0, 255])
        let image = try #require(try PICTDecoder.convertMonochromePackBits(ByteSource(data)))
        #expect(image.width == 2 && image.height == 1)
        #expect(image.pixels == [0, 0, 0, 255, 255, 255, 255, 255])
    }

    private func indexedPicture() -> Data {
        let frame = words([0, 0, 1, 3])
        var pixmap = Data(repeating: 0, count: 46)
        pixmap.replaceSubrange(0..<2, with: [0x80, 8])
        pixmap.replaceSubrange(2..<10, with: frame)
        pixmap.replaceSubrange(28..<34, with: words([8, 1, 8]))
        let palette = words([0, 0, 0, 1, 0, 0, 0, 0, 1, 65535, 65535, 65535])
        var data = words([0]) + frame + words([0x11, 0x02ff, 0x0c00]) + Data(repeating: 0, count: 24)
        data += words([0, 0xa0, 0x82, 0x1e, 0x98]) + pixmap + palette + frame + frame + words([0])
        data += Data([9, 7, 0, 1, 0, 0, 0, 0, 0, 0]) + words([0xa0, 0x83, 0xff])
        return data
    }

    private func legacyPicture(duplicate: Bool = true) -> Data {
        var data = indexedPicture()
        let header = words([65535, 65535, 0, 0, 0, 0, 3, 0, 1, 0, 0, 0])
        data.replaceSubrange(16..<40, with: header)
        if duplicate { data.insert(contentsOf: header.prefix(16), at: 16) }
        return data
    }

    @Test func duplicateLegacyHeaderDecodesWithProvenance() throws {
        let data = legacyPicture()
        let normalized = try PICTDecoder.normalize(ByteSource(data))
        let image = try #require(try PICTDecoder.convertIndexedPackBits(normalized.data))
        #expect(image.pixels == [0,0,0,255,255,255,255,255,0,0,0,255])
        #expect(normalized.diagnostics.map(\.code) == ["pict.duplicate_legacy_header"])
        #expect(normalized.data.count == data.count - 16)
        let record = PICTDecoder.convert(resource: ResourceInfo(sourceFile: "synthetic", resourceType: "PICT",
            resourceId: 1, name: "", rawLength: data.count), data: data)
        #expect(record.status == .ok)
        #expect(record.byteRanges == ["pict": [0, data.count]])
        #expect(record.resource.rawLength == data.count)
        let standard = try PICTDecoder.normalize(ByteSource(legacyPicture(duplicate: false)))
        #expect(standard.diagnostics.isEmpty)
        #expect(try PICTDecoder.convertIndexedPackBits(standard.data) != nil)
    }

    @Test(arguments: ["prefix", "bounds", "reserved", "truncated", "missing_end", "extra_draw"])
    func duplicateLegacyHeaderRejectsInvalidPicture(kind: String) throws {
        var data = legacyPicture()
        switch kind {
        case "prefix": data[20] ^= 1
        case "bounds": data[48] ^= 1
        case "reserved": data[52] ^= 1
        case "truncated": data = data.prefix(55)
        case "missing_end": data.removeLast(2)
        default: data.insert(contentsOf: words([0x30, 0, 0, 1, 3]), at: data.count - 2)
        }
        let normalized = try PICTDecoder.normalize(ByteSource(data))
        #expect(try PICTDecoder.convertIndexedPackBits(normalized.data) == nil)
    }

    @Test func indexedCommentsAndHighlightAreAccepted() throws {
        let image = try #require(try PICTDecoder.convertIndexedPackBits(ByteSource(indexedPicture())))
        #expect(image.pixels == [0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255])
    }

    @Test func packBitsRejectsIncompleteAndOverflowingRows() {
        let cases: [([UInt8], Int, Int)] = [([0], 1, 1), ([255], 1, 2), ([1, 17, 34], 2, 2),
                                         ([254, 17], 2, 2), ([0, 17], 3, 1)]
        for (bytes, count, stride) in cases {
            #expect(throws: (any Error).self) {
                try PICTDecoder.unpackPackBitsRow(ByteSource(Data(bytes)), offset: 0, byteCount: count, rowBytes: stride)
            }
        }
    }
    @Test(arguments: ["missing_end", "trailing_draw", "narrow_clip", "short_stride", "oversized"])
    func indexedRejectsIncompleteOrUnsupportedRendering(kind: String) throws {
        var data = indexedPicture()
        switch kind {
        case "missing_end": data.removeLast(2)
        case "trailing_draw": data.insert(contentsOf: words([0x30, 0, 0, 1, 3]), at: data.count - 2)
        case "narrow_clip": data.insert(contentsOf: words([1, 10, 0, 0, 1, 2]), at: 40)
        case "oversized":
            data.replaceSubrange(50..<52, with: words([0xa000]))
            for offset in [2, 52, 120, 128] { data.replaceSubrange(offset..<offset + 8, with: words([0, 0, 4097, 8192])) }
        default:
            for offset in [2, 52, 120, 128] { data.replaceSubrange(offset..<offset + 8, with: words([0, 0, 1, 9])) }
        }
        #expect(try PICTDecoder.convertIndexedPackBits(ByteSource(data)) == nil)
    }

    @Test func indexedNonzeroOriginCropsRelativeToBitmap() throws {
        var data = indexedPicture()
        for offset in [2, 52, 120, 128] { data.replaceSubrange(offset..<offset + 8, with: words([3, 5, 4, 8])) }
        let image = try #require(try PICTDecoder.convertIndexedPackBits(ByteSource(data)))
        #expect(image.pixels == [0,0,0,255,255,255,255,255,0,0,0,255])
    }

}
