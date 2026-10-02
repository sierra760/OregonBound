import Foundation
import Testing
import PDFKit
@testable import OregonBound

struct CDGuidePictureTests {
    @MainActor @Test func guideReaderRejectsCommandsForInactiveOrRetiredOpenings() throws {
        let guide = try CDUserGuide(fork: MacResourceFork(resources: GameDataPreparationTests.userGuideResources()))
        var current = true
        let reader = CDUserGuideReader(guide: guide, fonts: nil, unavailable: nil, permitsActions: { current })
        reader.active = false
        reader.update(0) { $0.page(forward: true) }; reader.compare(); reader.export([0])
        #expect(reader.views?.states.count == 1 && reader.views?.states[0].pageID == 10)
        #expect(reader.exportDocument == nil && !reader.exportingPDF)
        reader.active = true
        reader.update(0) { $0.page(forward: true) }; reader.compare()
        #expect(reader.views?.states.count == 2 && reader.views?.states[0].pageID == 30)
        current = false
        reader.update(0) { $0.page(forward: true) }; reader.compare(); reader.export([0])
        #expect(reader.views?.states.count == 2 && reader.views?.states[0].pageID == 30)
        #expect(reader.exportDocument == nil && !reader.exportingPDF)
    }

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
        #expect(bitmap.indices == [2, 7, 2, 7, 2, 7])
        #expect(bitmap.pixelSize == 8)
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
        #expect(bitmap.pixelSize == 1 && color.pixelSize == 8)
        #expect(bitmap.indices == [1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0])
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

    @Test func guideTextLayoutUsesPointScaledCharacterExtraAndIndependentSpaceExtra() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (4, Data([1])), (13, Self.words([10])),
            (6, Self.words([0xffff, 0x8000])), (0x16, Self.words([-165])),
            (0x15, Self.words([0x1234])),
            (0x28, Self.words([7, -2]) + Data([3, 65, 32, 66]))]))
        var advances = [Int](repeating: 0, count: 256)
        advances[65] = 5; advances[32] = 3; advances[66] = 7
        let run = try #require(picture.textRuns.first)
        let layout = try run.layout(advances: advances, ascent: 10)
        #expect(layout.glyphs.map(\.code) == [65, 32, 66])
        #expect(layout.glyphs.map(\.location) == [.init(x: -2, y: -3), .init(x: 3, y: -3), .init(x: 7, y: -3)])
        #expect(layout.glyphs.allSatisfy { $0.bold })
        #expect(layout.finalPen == 967668)
    }

    @Test func guideTextLayoutWrapsFixedPenAndRejectsUnsupportedMetrics() throws {
        let run = try #require(CDGuidePicture(data: Self.picture([
            (0x28, Self.words([0, 32767]) + Data([2, 65, 65]))])).textRuns.first)
        let advances = [Int](repeating: 1, count: 256)
        let layout = try run.layout(advances: advances, ascent: 1)
        #expect(layout.glyphs.map(\.location.x) == [32767, -32768])
        #expect(layout.finalPen == -2147385344)
        for metrics in [[], [Int](repeating: 0, count: 255), [Int](repeating: -1, count: 256),
                        [Int](repeating: 513, count: 256)] {
            #expect(throws: (any Error).self) { try run.layout(advances: metrics, ascent: 1) }
        }
        #expect(throws: (any Error).self) { try run.layout(advances: advances, ascent: -1) }
        for record: (Int, Data) in [(4, Data([2])), (0x10, Self.words([1, 2, 1, 1])),
                                   (0x2e, Self.words([4]) + Data([0, 0, 1, 0]))] {
            let unsupported = try #require(CDGuidePicture(data: Self.picture([
                record, (0x28, Self.words([0, 0]) + Data([1, 65]))])).textRuns.first)
            #expect(throws: (any Error).self) { try unsupported.layout(advances: advances, ascent: 1) }
        }
    }

    static func outlineFont(cmapGlyph: Int = 2, widths: [UInt8] = [4, 7, 9], pointSizes: [UInt8] = [9, 10]) -> Data {
        let cmap = words([0, 1, 1, 0, 0, 12, 6, 14, 0, 65, 2, 1, cmapGlyph])
        let maxp = words([1, 0, 3])
        var hdmx = words([0, pointSizes.count, 0, 8])
        for pointSize in pointSizes { hdmx += Data([pointSize, 9] + widths + [0, 0, 0]) }
        let tables = [("cmap", cmap), ("maxp", maxp), ("hdmx", hdmx)]
        var header = words([1, 0, tables.count, 0, 0, 0]), body = Data()
        for (tag, bytes) in tables {
            while body.count % 4 != 0 { body.append(0) }
            header += Data(tag.utf8); header.appendU32(0)
            header.appendU32(UInt32(12 + tables.count * 16 + body.count))
            header.appendU32(UInt32(bytes.count)); body += bytes
        }
        return header + body
    }

    @Test func guideOutlineUsesMacRomanGlyphMapAndOriginalDeviceWidths() throws {
        let font = try CDGuideOutlineFont(data: Self.outlineFont())
        #expect(font.glyphIDs.count == 256 && font.advances.count == 256)
        #expect(font.glyphIDs[65] == 1 && font.glyphIDs[66] == 2 && font.glyphIDs[64] == 0)
        #expect(font.advances[65] == 7 && font.advances[66] == 9 && font.advances[64] == 4)
        #expect(font.pointSize == 10)
    }

    @Test func guideOutlineRejectsMalformedTablesAndMissingDeviceWidths() {
        let good = Self.outlineFont()
        for count in 0..<good.count {
            #expect(throws: (any Error).self) { try CDGuideOutlineFont(data: good.prefix(count)) }
        }
        for bytes in [Self.outlineFont(cmapGlyph: 3), Self.outlineFont(pointSizes: [9, 11]),
                      Self.outlineFont(pointSizes: [10, 10])] {
            #expect(throws: (any Error).self) { try CDGuideOutlineFont(data: bytes) }
        }
        var duplicate = good; duplicate.replaceSubrange(28..<32, with: Data("cmap".utf8))
        var overlap = good; overlap.replaceSubrange(36..<40, with: good[20..<24])
        var outside = good; outside.replaceSubrange(20..<24, with: Data([0xff, 0xff, 0xff, 0xff]))
        var tooMany = good; tooMany[4] = 0x7f; tooMany[5] = 0xff
        for bytes in [duplicate, overlap, outside, tooMany] {
            #expect(throws: (any Error).self) { try CDGuideOutlineFont(data: bytes) }
        }
    }

    @Test func guideRasterPreservesQuickDrawHorizontalAndVerticalSampling() throws {
        #expect(try CDGuideRaster.horizontalGroups(source: 5, destination: 3) == [0..<2, 2..<3, 3..<5])
        #expect(try CDGuideRaster.verticalGroups(source: 5, destination: 3) == [0..<1, 1..<3, 3..<5])
        #expect(try CDGuideRaster.horizontalGroups(source: 2, destination: 3) == [0..<1, 0..<1, 1..<2])
        #expect(try CDGuideRaster.verticalGroups(source: 2, destination: 3) == [0..<1, 0..<1, 1..<2])
        #expect(try CDGuideRaster.verticalGroups(source: 4, destination: 2) == [0..<2, 2..<4])
        for size in [0, -1, 4097] {
            #expect(throws: (any Error).self) { try CDGuideRaster.horizontalGroups(source: size, destination: 1) }
            #expect(throws: (any Error).self) { try CDGuideRaster.verticalGroups(source: 1, destination: size) }
        }
    }

    @Test func guideRasterUsesOriginalOvalScanlinesAndInsetFrame() throws {
        #expect(try CDGuideRaster.ovalSpans(.init(top: 1, left: 1, bottom: 7, right: 7)) ==
                [2..<6, 1..<7, 1..<7, 1..<7, 1..<7, 2..<6])
        #expect(try CDGuideRaster.ovalSpans(.init(top: -1, left: -2, bottom: 3, right: 2)) ==
                [-1..<1, -2..<2, -2..<2, -1..<1])
        #expect(try CDGuideRaster.ovalSpans(.init(top: 0, left: 0, bottom: 0, right: 0)).isEmpty)
        #expect(throws: (any Error).self) {
            try CDGuideRaster.ovalSpans(.init(top: 0, left: 0, bottom: 4097, right: 1))
        }
    }

    @Test func guideRasterComposesOvalFrameOriginClipAndIndexedShrink() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (0x51, Self.words([1, 1, 7, 7])), (0x1a, Self.words([0xffff, 0, 0])), (0x58, Data()),
            (0xc, Self.words([1, 1])), (1, Self.region([2, 2, 4, 4])),
            (0x98, Self.indexedBitmap(source: [-2, -3, 0, 0], destination: [2, 2, 3, 3]))
        ], frame: [0, 0, 8, 8]))
        let image = try CDGuideRaster.render(picture)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(image.pixels[(y * 8 + x) * 4..<(y * 8 + x + 1) * 4]) }
        #expect(pixel(0, 0) == [0, 0, 0, 0])
        #expect(pixel(2, 1) == [255, 0, 0, 255])
        #expect(pixel(3, 3) == [0, 0, 0, 255])
        #expect(pixel(1, 1) == [0, 171, 255, 255])
        #expect(pixel(7, 7) == [0, 0, 0, 0])
    }

    @Test func guideRasterDrawsImportedGlyphMasksAndRejectsMissingFonts() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (3, Self.words([3])), (4, Data([1])), (13, Self.words([10])),
            (0x1a, Self.words([0, 0xffff, 0])), (0x28, Self.words([3, 1]) + Data([1, 65]))
        ], frame: [0, 0, 6, 6]))
        let empty = CDGuideRaster.Glyph(width: 0, height: 0, bearingX: 0, ink: [])
        var glyphs = [CDGuideRaster.Glyph](repeating: empty, count: 256)
        glyphs[65] = .init(width: 2, height: 2, bearingX: -1, ink: [255, 0, 0, 255])
        let font = CDGuideRaster.Font(advances: [Int](repeating: 3, count: 256), ascent: 2, glyphs: glyphs)
        let image = try CDGuideRaster.render(picture) { family, size in family == 3 && size == 10 ? font : nil }
        let green = stride(from: 0, to: image.pixels.count, by: 4).filter { image.pixels[$0 + 3] != 0 }.map { $0 / 4 }
        #expect(green == [6, 7, 13, 14])
        #expect(green.allSatisfy { image.pixels[$0 * 4 + 1] == 255 })
        #expect(throws: (any Error).self) { try CDGuideRaster.render(picture) }
    }

    @Test func guideRasterPreservesBitmapMaskAndRejectsUnsupportedDrawing() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (0x99, Self.indexedBitmap(destination: [0, 0, 4, 4], mask: Self.region([1, 1, 3, 3])))
        ], frame: [0, 0, 4, 4]))
        let image = try CDGuideRaster.render(picture)
        let covered = stride(from: 3, to: image.pixels.count, by: 4).filter { image.pixels[$0] != 0 }.map { $0 / 4 }
        #expect(covered == [5, 6, 9, 10])
        for record: (Int, Data) in [(0x20, Self.words([0, 0, 3, 3])), (0x33, Self.words([0, 0, 3, 3]))] {
            let unsupported = try CDGuidePicture(data: Self.picture([record]))
            #expect(throws: (any Error).self) { try CDGuideRaster.render(unsupported) }
        }
    }

    @Test func guideRasterExtractsGlyphInkAndMissingCharacterFromOriginalStrike() throws {
        let bytes = Self.words([0x9000, 65, 65, 3, 0, -2, 4, 2, 10, 2, 0, 0, 1])
            + Data([0xc0, 0, 0x90, 0]) + Self.words([0, 2, 4, 0x0103, 0x0002, 0xffff])
        let strike = try BitmapFontExtractor.parseNFNT(bytes, resourceID: 1)
        let font = try CDGuideRaster.Font(strike: strike)
        #expect(font.ascent == 2 && font.advances[65] == 3 && font.advances[255] == 2)
        #expect(font.glyphs[65].bearingX == 1)
        #expect(font.glyphs[65].width == 2 && font.glyphs[65].height == 2)
        #expect(font.glyphs[65].ink == [255, 255, 255, 0])
        #expect(font.glyphs[255].ink == [0, 0, 0, 255])
    }

    @Test func guideOutlineRasterizerRequiresTheVerifiedOriginalFont() {
        for bytes in [Data(), Self.outlineFont()] {
            #expect(throws: (any Error).self) { try CDGuideDrawing.outlineFont(data: bytes) }
        }
    }

    @Test func guideFontSetRejectsIncompleteOrUnverifiedResources() throws {
        #expect(throws: (any Error).self) { try CDGuideFonts(resources: [:]) }
        var resources: [CDGuideFonts.Key: Data] = [:]
        for selection in CDGuideFonts.selections { resources[selection.key] = Data([1, 2, 3]) }
        #expect(throws: (any Error).self) { try CDGuideFonts(resources: resources) }
        #expect(throws: (any Error).self) { try CDGuideFonts(systemFork: MacResourceFork(resources: [])) }
        // A plausible family association is insufficient without the pinned strike.
        var family = Data(repeating: 0, count: 52); family[3] = 3
        family += Self.words([0, 9, 0, 123])
        let fork = MacResourceFork(resources: [
            MacResource(type: "FOND", id: 3, name: "Geneva", attributes: 0, data: family),
            MacResource(type: "NFNT", id: 123, name: nil, attributes: 0, data: Data([1, 2, 3]))])
        #expect(throws: (any Error).self) { try CDGuideFonts(systemFork: fork) }
    }

    @Test func guideRasterBoundsTotalWorkIncludingMaskedBitmapVisits() throws {
        let fill = (0x31, Self.words([0, 0, 4, 4]))
        let once = try CDGuidePicture(data: Self.picture([fill], frame: [0, 0, 4, 4]))
        #expect(try CDGuideRaster.render(once, workLimit: 16).pixels.count == 64)
        #expect(throws: (any Error).self) { try CDGuideRaster.render(once, workLimit: 15) }
        let twice = try CDGuidePicture(data: Self.picture([fill, fill], frame: [0, 0, 4, 4]))
        #expect(throws: (any Error).self) { try CDGuideRaster.render(twice, workLimit: 16) }
        let masked = try CDGuidePicture(data: Self.picture([
            (0x99, Self.indexedBitmap(destination: [0, 0, 4, 4], mask: Self.region([0, 0, 0, 0])))
        ], frame: [0, 0, 4, 4]))
        #expect(throws: (any Error).self) { try CDGuideRaster.render(masked, workLimit: 15) }
        #expect(try CDGuideRaster.render(masked, workLimit: 16).pixels.allSatisfy { $0 == 0 })
        for limit in [0, -1, 64 * 1024 * 1024 + 1, Int.max] {
            #expect(throws: (any Error).self) { try CDGuideRaster.render(once, workLimit: limit) }
        }
    }

    @Test func guideRasterRejectsMalformedFontMetricsAndMasksBeforeDrawing() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (0x28, Self.words([2, 1]) + Data([1, 65]))
        ], frame: [0, 0, 4, 4]))
        let empty = CDGuideRaster.Glyph(width: 0, height: 0, bearingX: 0, ink: [])
        let advances = [Int](repeating: 1, count: 256)
        let glyphs = [CDGuideRaster.Glyph](repeating: empty, count: 256)
        var invalid: [CDGuideRaster.Font] = [
            .init(advances: [], ascent: 1, glyphs: glyphs),
            .init(advances: advances, ascent: 513, glyphs: glyphs),
            .init(advances: advances, ascent: 1, glyphs: []),
            .init(advances: [Int](repeating: -1, count: 256), ascent: 1, glyphs: glyphs)
        ]
        for bad in [CDGuideRaster.Glyph(width: 1, height: 1, bearingX: 0, ink: [128]),
                    .init(width: 2, height: 2, bearingX: 0, ink: [255]),
                    .init(width: 0, height: 0, bearingX: 513, ink: []),
                    .init(width: 513, height: 0, bearingX: 0, ink: [])] {
            var altered = glyphs; altered[65] = bad
            invalid.append(.init(advances: advances, ascent: 1, glyphs: altered))
        }
        for font in invalid {
            #expect(throws: (any Error).self) { try CDGuideRaster.render(picture) { _, _ in font } }
        }
    }

    @Test func guideFontSetRejectsAmbiguousAndOversizedSystemResources() {
        func reject(_ resources: [MacResource], reason: String) {
            do {
                _ = try CDGuideFonts(systemFork: MacResourceFork(resources: resources))
                Issue.record("Accepted invalid System font resources")
            } catch {
                #expect(String(describing: error).contains(reason))
            }
        }
        var header = Data(repeating: 0, count: 52); header[3] = 3
        let family = MacResource(type: "FOND", id: 3, name: nil, attributes: 0,
                                 data: header + Self.words([0, 9, 0, 123]))
        reject([family, family], reason: "duplicate guide System font resource")
        let ambiguous = MacResource(type: "FOND", id: 3, name: nil, attributes: 0,
                                    data: header + Self.words([1, 9, 0, 123, 9, 0, 124]))
        reject([ambiguous], reason: "ambiguous guide font association")
        let font = MacResource(type: "NFNT", id: 123, name: nil, attributes: 0, data: Data())
        reject([family, font, font], reason: "duplicate guide System font resource")
        var compressed = Data([0xa8, 0x9f, 0x65, 0x72, 0, 18, 9, 1])
        compressed.appendU32(0xffffffff); compressed += Self.words([2, 0, 0])
        reject([family, MacResource(type: "NFNT", id: 123, name: nil, attributes: 1, data: compressed)],
               reason: "excessive expanded System font")
        reject([MacResource(type: "FOND", id: 3, name: nil, attributes: 1, data: compressed)],
               reason: "excessive expanded System font")
        reject([MacResource(type: "FOND", id: 3, name: nil, attributes: 0,
                            data: Data(repeating: 0, count: 65537))], reason: "excessive System font resource")
    }

    @Test func guideAccessibleTextUsesVisibleGlyphsAndCaptionClipCoordinates() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (3, Self.words([3])), (13, Self.words([10])),
            (0xc, Self.words([1, 2])), (0x28, Self.words([5, 4]) + Data([5]) + Data("AB CD".utf8))
        ], frame: [-2, -3, 8, 17]))
        let glyph = CDGuideRaster.Glyph(width: 2, height: 2, bearingX: 0, ink: [255, 0, 255, 255])
        let font = CDGuideRaster.Font(advances: [Int](repeating: 2, count: 256), ascent: 2,
                                     glyphs: [CDGuideRaster.Glyph](repeating: glyph, count: 256))
        let text = try CDGuideText(picture: picture) { _, _ in font }
        #expect(text.text() == "AB CD")
        #expect(text.text(in: .init(top: 3, left: 12, bottom: 5, right: 16)) == "CD")
        #expect(text.text(in: .init(top: 3, left: 8, bottom: 5, right: 10)) == "B")
        #expect(text.text(in: .init(top: 0, left: 0, bottom: 2, right: 20)).isEmpty)
        #expect(text.runs.first?.glyphs.first?.bounds == .init(top: 3, left: 6, bottom: 5, right: 8))
        #expect(throws: (any Error).self) { try CDGuideText(picture: picture) { _, _ in nil } }
    }

    @Test func guidePDFPreservesPageOrderNumbersAndSelectableSourceTextAndBoundsWork() throws {
        var resources = GameDataPreparationTests.userGuideResources()
        let bytes = Self.picture([(3, Self.words([3])), (13, Self.words([12])),
            (0x28, Self.words([15, 2]) + Data([6]) + Data("Sample".utf8))], frame: [0, 0, 30, 100])
        resources.removeAll { $0.type == "PICT" && $0.id == 10 }
        resources.append(.init(type: "PICT", id: 10, name: nil, attributes: 0, data: bytes))
        let guide = try CDUserGuide(fork: MacResourceFork(resources: resources))
        let document = try CDGuideDocument(guide: guide, originalFonts: nil)
        let all = try #require(PDFDocument(data: document.pdf(pageIndices: [0, 1, 2])))
        #expect(all.pageCount == 3)
        #expect(all.page(at: 0)?.bounds(for: .mediaBox) == CGRect(x: 0, y: 0, width: 612, height: 792))
        #expect(all.page(at: 0)?.string?.contains("Sample") == true)
        #expect(all.page(at: 2)?.string?.contains("3") == true)
        let selected = try #require(PDFDocument(data: document.pdf(pageIndices: [1])))
        #expect(selected.pageCount == 1 && selected.string?.contains("2") == true)
        for invalid in [[], [-1], [3], [1, 0], [0, 0]] {
            #expect(throws: (any Error).self) { try document.pdf(pageIndices: invalid) }
        }
        #expect(throws: (any Error).self) { try document.pdf(pageIndices: [0], pixelLimit: 1) }
    }

    @Test func guideDocumentCentersPaperContentAndClipsCaptionImageAndTextTogether() throws {
        var resources = GameDataPreparationTests.userGuideResources()
        let bytes = Self.picture([
            (3, Self.words([3])), (13, Self.words([12])),
            (0x28, Self.words([15, 2]) + Data([5]) + Data("First".utf8)),
            (0x28, Self.words([35, 2]) + Data([6]) + Data("Second".utf8))
        ], frame: [-2, -3, 48, 97])
        resources.removeAll { $0.type == "PICT" && $0.id == 10 }
        resources.append(.init(type: "PICT", id: 10, name: nil, attributes: 0, data: bytes))
        let guide = try CDUserGuide(fork: MacResourceFork(resources: resources))
        let document = try CDGuideDocument(guide: guide, originalFonts: nil)
        #expect(!document.usesOriginalFonts)
        let picture = try document.picture(10)
        #expect(picture.image.width == 100 && picture.image.height == 50)
        #expect(picture.paperOrigin == .init(x: 256, y: 0))
        #expect(picture.text() == "First\nSecond")
        let link = CDUserGuide.Link(bounds: .init(top: 0, left: 0, bottom: 20, right: 20), kind: .caption,
            openCheck: false, destination: 10, destinationRect: .init(top: 0, left: -3, bottom: 20, right: 97))
        let caption = try document.caption(link)
        #expect(caption.image.width == 100 && caption.image.height == 20)
        #expect(caption.text == "First")
        let padded = CDUserGuide.Link(bounds: link.bounds, kind: .caption, openCheck: false, destination: 10,
            destinationRect: .init(top: -4, left: -5, bottom: 50, right: 99))
        let extended = try document.caption(padded)
        #expect(extended.image.width == 104 && extended.image.height == 54)
        #expect(extended.text == "First\nSecond")
        let outside = CDUserGuide.Link(bounds: link.bounds, kind: .caption, openCheck: false,
            destination: 10, destinationRect: .init(top: 100, left: 100, bottom: 120, right: 120))
        #expect(throws: (any Error).self) { try document.caption(outside) }
        #expect(throws: (any Error).self) { try document.picture(999) }
        #expect(document.cachedImageBytes <= CDGuideDocument.maximumCachedImageBytes)
    }

    @Test func guideSubstituteFontsAreExplicitBoundedAndRenderMacRomanText() throws {
        let fonts = try CDGuideDrawing.substituteFonts()
        #expect(Set(fonts.keys) == Set(CDGuideFonts.selections.map(\.key)))
        for font in fonts.values {
            try font.validate()
            #expect(font.advances[32] > 0)
            #expect(font.glyphs[32].ink.allSatisfy { $0 == 0 })
            for code in [65, 0x8e] { #expect(font.glyphs[code].ink.contains(255)) }
        }
        let picture = try CDGuidePicture(data: Self.picture([
            (3, Self.words([3])), (13, Self.words([12])),
            (0x28, Self.words([15, 2]) + Data([3, 65, 32, 0x8e]))
        ], frame: [0, 0, 30, 50]))
        let image = try CDGuideRaster.render(picture) { fonts[.init(family: $0, size: $1)] }
        #expect(stride(from: 3, to: image.pixels.count, by: 4).contains { image.pixels[$0] == 255 })
    }

    @Test func guideFontIndependentTranscriptSelectsCaptionLinesInPictureCoordinates() throws {
        let picture = try CDGuidePicture(data: Self.picture([
            (0xc, Self.words([1, 2])),
            (0x28, Self.words([6, 4]) + Data([5]) + Data("First".utf8)),
            (0x28, Self.words([16, 4]) + Data([6]) + Data("Second".utf8))
        ], frame: [-2, -3, 30, 60]))
        let transcript = CDGuideText.Transcript(picture: picture)
        #expect(transcript.text() == "First\nSecond")
        #expect(transcript.text(in: .init(top: 0, left: 6, bottom: 10, right: 60)) == "First")
        #expect(transcript.text(in: .init(top: 10, left: 6, bottom: 20, right: 60)) == "Second")
        #expect(transcript.text(in: .init(top: 20, left: 0, bottom: 30, right: 60)).isEmpty)
    }

    @Test func guideAccessibleTextHonorsNonrectangularClipsAndBoundsWork() throws {
        let clip = Self.region([0, 0, 2, 6], changes: [0, 0, 2, 4, 6, 32767, 2, 0, 2, 4, 6, 32767, 32767])
        let picture = try CDGuidePicture(data: Self.picture([
            (1, clip), (0x28, Self.words([2, 0]) + Data([3]) + Data("ABC".utf8))
        ], frame: [0, 0, 4, 8]))
        let glyph = CDGuideRaster.Glyph(width: 2, height: 2, bearingX: 0, ink: [255, 255, 255, 255])
        let font = CDGuideRaster.Font(advances: [Int](repeating: 2, count: 256), ascent: 2,
                                     glyphs: [CDGuideRaster.Glyph](repeating: glyph, count: 256))
        #expect(try CDGuideText(picture: picture) { _, _ in font }.text() == "AC")
        #expect(throws: (any Error).self) { try CDGuideText(picture: picture, workLimit: 11) { _, _ in font } }
    }

}
