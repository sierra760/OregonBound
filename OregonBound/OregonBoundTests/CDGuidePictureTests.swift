import Foundation
import Testing
@testable import OregonBound

struct CDGuidePictureTests {
    static func words(_ values: [Int]) -> Data {
        var data = Data()
        for value in values { data.appendU16(UInt16(truncatingIfNeeded: value)) }
        return data
    }
    static func region(_ bounds: [Int], changes: [Int] = []) -> Data {
        words([10 + changes.count * 2] + bounds + changes)
    }

    @Test func guideRegionReplaysInversionsAndKeepsHolesAndNegativeCoordinates() throws {
        let data = Self.region([-2, -3, 2, 5], changes: [
            -2, -3, 5, 32767,
             0, -1, 3, 32767,
             1, -1, 3, 32767,
             2, -3, 5, 32767, 32767])
        let region = try CDGuidePicture.Region(data: data)
        #expect(region.bounds == .init(top: -2, left: -3, bottom: 2, right: 5))
        for y in -3...2 { for x in -4...5 {
            let expected = (-2..<2).contains(y) && (-3..<5).contains(x)
                && !(y == 0 && (-1..<3).contains(x))
            #expect(region.contains(x: x, y: y) == expected)
        } }
        #expect(region.bands.count == 3)
        #expect(region.bands[1].spans == [-3 ..< -1, 3 ..< 5])
        let rectangle = try CDGuidePicture.Region(data: Self.region([0, 0, 2, 3]))
        #expect(rectangle.contains(x: 2, y: 1))
        #expect(!rectangle.contains(x: 3, y: 1))
        #expect(try CDGuidePicture.Region(data: Self.region([0, 0, 0, 0])).bands.isEmpty)
    }

    @Test func guideRegionRejectsMalformedInversionData() throws {
        let good = Self.region([0, 0, 2, 4], changes: [0, 0, 4, 32767, 2, 0, 4, 32767, 32767])
        for size in 0..<good.count {
            #expect(throws: (any Error).self) { try CDGuidePicture.Region(data: good.prefix(size)) }
        }
        #expect(throws: (any Error).self) { try CDGuidePicture.Region(data: good + Data([0, 0])) }
        for changes in [
            [32767],                                      // open/missing rows
            [0, 0, 32767, 32767],                         // odd inversion count
            [0, 0, 4, 32767, 32767],                     // region never closes
            [0, 0, 4, 32767, 0, 0, 4, 32767, 32767],   // repeated vertical coordinate
            [0, 4, 0, 32767, 2, 0, 4, 32767, 32767],   // descending horizontal coordinates
            [0, -1, 4, 32767, 2, -1, 4, 32767, 32767], // outside bounds
            [0, 0, 4, 32767, 3, 0, 4, 32767, 32767],   // outside vertical bounds
            [0, 0, 0, 4, 4, 32767, 32767]               // duplicate coordinates
        ] {
            #expect(throws: (any Error).self) {
                try CDGuidePicture.Region(data: Self.region([0, 0, 2, 4], changes: changes))
            }
        }
        #expect(throws: (any Error).self) {
            try CDGuidePicture.Region(data: Self.region([0, 4, 2, 0]))
        }
    }
    @Test func guideRegionBoundsExpandedComplexity() {
        // A small source can expand into quadratically many retained spans.
        var changes: [Int] = []
        for y in 0..<512 { changes += [y, y * 2, y * 2 + 1, 32767] }
        changes += [512] + Array(0..<1024) + [32767, 32767]
        #expect(throws: (any Error).self) {
            try CDGuidePicture.Region(data: Self.region([0, 0, 512, 1024], changes: changes))
        }
    }

    static func picture(_ records: [(Int, Data)], frame: [Int] = [-1, -2, 40, 60]) -> Data {
        var data = words([0] + frame + [0x11, 0x2ff])
        for (opcode, payload) in records {
            if data.count % 2 != 0 { data.append(0) }
            data.appendU16(UInt16(opcode)); data.append(payload)
        }
        if data.count % 2 != 0 { data.append(0) }
        data.appendU16(0xff)
        data[0] = UInt8(truncatingIfNeeded: data.count >> 8)
        data[1] = UInt8(truncatingIfNeeded: data.count)
        return data
    }

    @Test func guidePicturePreservesTextStateAndResetsFractionAfterEachRun() throws {
        let bytes = Self.picture([
            (3, Self.words([3])), (4, Data([1])), (13, Self.words([10])),
            (6, Self.words([0xffff, 0x8000])), (0x16, Self.words([-165])),
            (0xc, Self.words([-5, -9])), // Origin stores dh before dv.
            (0x1a, Self.words([0x1234, 0x5678, 0x9abc])),
            (0x2c, Self.words([9, 3]) + Data([6]) + Data("Geneva".utf8)),
            (0x2e, Self.words([4]) + Data([0, 0, 0, 1])),
            (0x15, Self.words([0x1234])),
            (0x28, Self.words([4, 7]) + Data([2, 0x8e, 0x41])),
            (0x2b, Data([255, 5, 1, 0x42])), (0x2a, Data([3, 1, 0x43]))])
        let picture = try CDGuidePicture(data: bytes)
        #expect(picture.frame == .init(top: -1, left: -2, bottom: 40, right: 60))
        #expect(picture.textRuns.map(\.text) == ["éA", "B", "C"])
        #expect(picture.textRuns.map(\.location) == [.init(x: 7, y: 4), .init(x: 262, y: 9), .init(x: 262, y: 12)])
        #expect(picture.textRuns.map(\.fraction) == [0x1234, 0x8000, 0x8000])
        let run = try #require(picture.textRuns.first)
        #expect(run.bytes == [0x8e, 0x41])
        #expect(run.state.font == 3 && run.state.face == 1 && run.state.size == 10)
        #expect(run.state.spaceExtra == -32768 && run.state.characterExtra == -165)
        #expect(run.state.origin == .init(x: -5, y: -9))
        #expect(run.state.foreground == .init(red: 0x1234, green: 0x5678, blue: 0x9abc))
        #expect(run.state.glyphs.scalingDisabled)
        #expect(picture.fontNames == [3: "Geneva"])
        #expect(picture.records.last?.opcode == 0xff)
        #expect(picture.records.last.map { $0.offset + $0.length } == bytes.count)
    }

    @Test func guidePictureKeepsSharedShapeRectangleAndSignedShortLineDeltas() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (1, Self.region([0, 0, 30, 40])), (7, Self.words([2, 3])),
            (0x34, Self.words([1, 2, 4, 6])), (0x58, Data()),
            (0x22, Self.words([7, 9]) + Data([0xfe, 0xfd])),
            (0x23, Data([0xff, 0x04]))]))
        #expect(picture.operations.count == 4)
        guard case .shape(let shape, let verb, let rect, let state) = picture.operations[1] else {
            Issue.record("Expected frameSameOval"); return
        }
        #expect(shape == .oval && verb == .frame)
        #expect(rect == .init(top: 1, left: 2, bottom: 4, right: 6))
        #expect(state.penSize == .init(x: 3, y: 2))
        #expect(state.clip.bounds == .init(top: 0, left: 0, bottom: 30, right: 40))
        guard case .line(let from, let to, _) = picture.operations[3] else {
            Issue.record("Expected shortLineFrom"); return
        }
        #expect(from == .init(x: 7, y: 4) && to == .init(x: 6, y: 8))
    }

    @Test func guidePictureRejectsTruncationUnknownDrawingAndInvalidState() {
        let good = Self.picture([(0x28, Self.words([1, 2]) + Data([1, 65]))])
        for count in 0..<good.count {
            #expect(throws: (any Error).self) { try CDGuidePicture(data: good.prefix(count)) }
        }
        #expect(throws: (any Error).self) { try CDGuidePicture(data: good + Data([0])) }
        for record: (Int, Data) in [
            (0x1234, Data()), (0x38, Data()), // unknown draw; no preceding rectangle
            (0x2e, Self.words([4]) + Data([0, 0, 2, 0])),
            (0x2c, Self.words([4, 3]) + Data([2, 65])),
            (13, Self.words([0])), (13, Self.words([513])),
            (4, Data([0x80])), (7, Self.words([-1, 2])),
            (0x10, Self.words([1, 1, 0, 1]))
        ] {
            #expect(throws: (any Error).self) { try CDGuidePicture(data: Self.picture([record])) }
        }
    }

    static func indexedBitmap(rowBytes: Int = 8, bounds: [Int] = [-2, -3, 0, 0],
                              source: [Int] = [-2, -2, 0, 0], destination: [Int] = [5, 7, 9, 11],
                              flags: Int = 0, mode: Int = 0, mask: Data? = nil,
                              pixels: Data = Data([6, 2, 2, 7, 2, 252, 99, 6, 2, 7, 2, 7, 252, 99])) -> Data {
        // Three visible indices and five padding bytes per row. Padding is not color data.
        var data = words([0x8000 | rowBytes] + bounds)
        data += words([0, 0, 0, 0, 72, 0, 72, 0, 0, 8, 1, 8, 0, 0, 0, 0, 0, 0])
        data += words([0, 0, flags, 1, 2, 0xffff, 0x1234, 0, 7, 0, 0xabcd, 0xffff])
        data += words(source + destination + [mode])
        if let mask { data += mask }
        return data + pixels
    }

    @Test func guidePictureDecodesIndexedRowsAndPreservesCropScaleAndMask() throws {
        let mask = Self.region([5, 7, 9, 11], changes: [5, 7, 9, 32767, 7, 9, 11, 32767,
                                                        9, 7, 11, 32767, 32767])
        let picture = try CDGuidePicture(data: Self.picture([(0x99, Self.indexedBitmap(mask: mask))]))
        guard case .bitmap(let bitmap, _) = picture.operations.first else {
            Issue.record("Expected indexed bitmap"); return
        }
        #expect(bitmap.bounds == .init(top: -2, left: -3, bottom: 0, right: 0))
        #expect(bitmap.source == .init(top: -2, left: -2, bottom: 0, right: 0))
        #expect(bitmap.destination == .init(top: 5, left: 7, bottom: 9, right: 11))
        #expect(bitmap.pixels == [255, 18, 0, 255, 0, 171, 255, 255, 255, 18, 0, 255,
                                 0, 171, 255, 255, 255, 18, 0, 255, 0, 171, 255, 255])
        #expect(bitmap.mask?.contains(x: 8, y: 5) == true)
        #expect(bitmap.mask?.contains(x: 10, y: 5) == false)
        #expect(bitmap.mask?.contains(x: 10, y: 8) == true)
    }

    @Test func guidePictureDecodesMonoAndSequentialPaletteWithRawShortRows() throws {
        let mono = Self.words([2, -1, -2, 1, 7, -1, -1, 1, 6, 3, 4, 5, 11, 0])
            + Self.region([3, 4, 5, 11]) + Data([0xa0, 0x80, 0x50, 0])
        let indexed = Self.indexedBitmap(rowBytes: 4, flags: 0x8000,
            pixels: Data([0, 1, 0, 99, 1, 0, 1, 99]))
        let picture = try CDGuidePicture(data: Self.picture([
            (0x1a, Self.words([0xffff, 0, 0])), (0x1b, Self.words([0, 0, 0xffff])),
            (0x91, mono), (0x98, indexed)]))
        guard case .bitmap(let bitmap, _) = picture.operations[0],
              case .bitmap(let color, _) = picture.operations[1] else {
            Issue.record("Expected mono and indexed bitmaps"); return
        }
        let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
        #expect(bitmap.pixels == [red, blue, red, blue, blue, blue, blue, blue, red,
                                  blue, red, blue, red, blue, blue, blue, blue, blue].flatMap { $0 })
        #expect(color.pixels == [255, 18, 0, 255, 0, 171, 255, 255, 255, 18, 0, 255,
                                0, 171, 255, 255, 255, 18, 0, 255, 0, 171, 255, 255])
        #expect(color.mask == nil)
    }

    @Test func guidePictureRejectsMalformedBitmapRowsAndMetadata() {
        let good = Self.indexedBitmap()
        let wholePicture = Self.picture([(0x98, good)])
        for count in 0..<wholePicture.count {
            #expect(throws: (any Error).self) { try CDGuidePicture(data: wholePicture.prefix(count)) }
        }
        for payload in [
            Self.indexedBitmap(rowBytes: 2),
            Self.indexedBitmap(bounds: [0, 0, 4097, 3]),
            Self.indexedBitmap(source: [-2, -4, 0, 0]),
            Self.indexedBitmap(destination: [5, 7, 5, 11]),
            Self.indexedBitmap(flags: 1), Self.indexedBitmap(mode: 1),
            Self.indexedBitmap(pixels: Data([2, 248, 2, 2, 249, 7])), // first row overflows
            Self.indexedBitmap(pixels: Data([2, 250, 2, 2, 249, 7])), // first row incomplete
            Self.indexedBitmap(pixels: Data([2, 249, 3, 2, 249, 7]))  // unmapped visible index
        ] {
            #expect(throws: (any Error).self) { try CDGuidePicture(data: Self.picture([(0x98, payload)])) }
        }
        for offset in [10, 12, 26, 28, 30, 32] { // unsupported pixmap formats
            var malformed = good; malformed[offset + 1] = 99
            #expect(throws: (any Error).self) { try CDGuidePicture(data: Self.picture([(0x98, malformed)])) }
        }
    }

    @Test func guidePictureHandlesWideRowLengthsAndRejectsExcessiveDecodedStorage() throws {
        for width in [250, 251] {
            let encoded = Data([129, 2, UInt8(257 - (width - 128)), 2])
            let prefix = width > 250 ? Self.words([encoded.count]) : Data([UInt8(encoded.count)])
            let payload = Self.indexedBitmap(rowBytes: width, bounds: [0, 0, 1, width],
                source: [0, 0, 1, width], pixels: prefix + encoded)
            let picture = try CDGuidePicture(data: Self.picture([(0x98, payload)]))
            guard case .bitmap(let bitmap, _) = picture.operations[0] else {
                Issue.record("Expected wide bitmap"); return
            }
            #expect(bitmap.pixels.count == width * 4)
            #expect(bitmap.pixels.suffix(4) == [255, 18, 0, 255])
        }
        let row = Self.words([32]) + Data(Array(repeating: [UInt8(129), 2], count: 16).flatMap { $0 })
        let payload = Self.indexedBitmap(rowBytes: 2048, bounds: [0, 0, 2048, 2048],
            source: [0, 0, 2048, 2048], pixels: Data(Array(repeating: Array(row), count: 2048).flatMap { $0 }))
        #expect(throws: (any Error).self) {
            try CDGuidePicture(data: Self.picture(Array(repeating: (0x98, payload), count: 5)))
        }
    }

    @Test func guidePictureBoundsTotalRetainedRegionComplexity() {
        var changes: [Int] = []
        for y in 0..<100 { changes += [y, y * 2, y * 2 + 1, 32767] }
        changes += [100] + Array(0..<200) + [32767, 32767]
        let region = Self.region([0, 0, 100, 200], changes: changes)
        // Each region is valid by itself; distinct clips retained by drawing
        // operations must share a total budget for the complete picture.
        let records = (0..<14).flatMap { _ in [(1, region), (0x31, Self.words([0, 0, 1, 1]))] }
        #expect(throws: (any Error).self) { try CDGuidePicture(data: Self.picture(records)) }
    }

}
