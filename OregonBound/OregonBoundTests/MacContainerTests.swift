import XCTest
@testable import OregonBound

/// Container readers: every single-file fixture is built in the test from a tiny
/// hand-made resource fork; the HFS image is the 20 KB `tiny-hfs.dsk` bundle resource
/// (a shrunk machfs volume with one deliberately fragmented resource fork).
final class MacContainerTests: XCTestCase {
    // MARK: Fixture builders

    /// A resource fork (Inside Macintosh: More Macintosh Toolbox, 1-121) holding
    /// 'STR ' 128 "hello" and a 'DATA' 1 resource whose payload has long runs and 0x90 bytes.
    static let payload = Data([UInt8](repeating: 0x41, count: 40) + [0x90, 0x90, 0x90, 0x90, 0x90, 0x01, 0x02] + (0 ..< 64).map { UInt8($0) })
    static let fork: Data = {
        let resources: [(type: String, id: Int16, name: String?, data: Data)] = [
            ("STR ", 128, "hello", Data([5] + Array("Hello".utf8))),
            ("DATA", 1, nil, payload),
        ]
        var dataSection = Data(), offsets: [UInt32] = []
        for resource in resources {
            offsets.append(UInt32(dataSection.count))
            dataSection.appendU32(UInt32(resource.data.count)); dataSection.append(resource.data)
        }
        var names = Data(), refs = Data(), types = Data()
        types.appendU16(UInt16(resources.count - 1))
        for (index, resource) in resources.enumerated() {
            types.append(contentsOf: Array(resource.type.utf8)); types.appendU16(0)
            types.appendU16(UInt16(2 + 8 * resources.count + 12 * index))
            refs.appendU16(UInt16(bitPattern: resource.id))
            if let name = resource.name {
                refs.appendU16(UInt16(names.count)); names.append(UInt8(name.utf8.count)); names.append(contentsOf: Array(name.utf8))
            } else { refs.appendU16(0xFFFF) }
            refs.appendU32(offsets[index]); refs.appendU32(0)
        }
        var map = Data(repeating: 0, count: 24)                     // reserved header copy, handle, refnum, attributes
        map.appendU16(28); map.appendU16(UInt16(28 + types.count + refs.count))
        map.append(types); map.append(refs); map.append(names)
        var out = Data()
        out.appendU32(256); out.appendU32(UInt32(256 + dataSection.count))
        out.appendU32(UInt32(dataSection.count)); out.appendU32(UInt32(map.count))
        out.append(Data(repeating: 0, count: 256 - 16)); out.append(dataSection); out.append(map)
        return out
    }()
    static let dataFork = Data("data fork bytes\r".utf8)

    static func padded(_ data: Data, to multiple: Int) -> Data {
        data + Data(repeating: 0, count: (multiple - data.count % multiple) % multiple)
    }

    static func macBinary(version: Int, name: String = "Small App") -> Data {
        var header = Data(repeating: 0, count: 128)
        header[1] = UInt8(name.utf8.count); header.replaceSubrange(2 ..< 2 + name.utf8.count, with: Array(name.utf8))
        header.replaceSubrange(65 ..< 73, with: Array("APPLORGN".utf8))
        var lengths = Data(); lengths.appendU32(UInt32(dataFork.count)); lengths.appendU32(UInt32(fork.count))
        header.replaceSubrange(83 ..< 91, with: lengths)
        if version >= 2 {
            if version == 3 { header.replaceSubrange(102 ..< 106, with: Array("mBIN".utf8)) }
            header[122] = version == 3 ? 130 : 129; header[123] = 129
            let crc = MacContainers.crc16(header[0 ..< 124])
            header[124] = UInt8(crc >> 8); header[125] = UInt8(crc & 0xFF)
        }
        return header + padded(dataFork, to: 128) + padded(fork, to: 128)
    }

    static func appleSingle(magic: UInt32, includeData: Bool, name: String = "Small App") -> Data {
        var entries: [(UInt32, Data)] = []
        if includeData { entries.append((1, dataFork)) }
        entries += [(2, fork), (3, Data(name.utf8)), (9, Data("ORDFORGN".utf8) + Data(repeating: 0, count: 24))]
        var out = Data(); out.appendU32(magic); out.appendU32(0x0002_0000); out.append(Data(repeating: 0, count: 16))
        out.appendU16(UInt16(entries.count))
        var offset = 26 + 12 * entries.count, body = Data()
        for (id, payload) in entries {
            out.appendU32(id); out.appendU32(UInt32(offset + body.count)); out.appendU32(UInt32(payload.count)); body.append(payload)
        }
        return out + body
    }

    /// Minimal BinHex 4.0 encoder: header + CRCs, RLE90 for runs of four or more, 6-bit text.
    static func binHex() -> Data {
        let name = Array("Small App".utf8)
        var header = Data([UInt8(name.count)] + name + [0]) ; header.append(contentsOf: Array("APPLORGN".utf8))
        header.appendU16(0); header.appendU32(UInt32(dataFork.count)); header.appendU32(UInt32(fork.count))
        var stream = header; stream.appendU16(MacContainers.crc16(header))
        stream.append(dataFork); stream.appendU16(MacContainers.crc16(dataFork))
        stream.append(fork); stream.appendU16(MacContainers.crc16(fork))
        var rle: [UInt8] = []
        let bytes = [UInt8](stream)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            var run = 1
            while index + run < bytes.count, bytes[index + run] == byte, run < 255 { run += 1 }
            if byte == 0x90 { for _ in 0 ..< run { rle += [0x90, 0x00] } }
            else if run >= 4 { rle += [byte, 0x90, UInt8(run)] }
            else { rle += [UInt8](repeating: byte, count: run) }
            index += run
        }
        let alphabet = Array("!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8)
        var text: [UInt8] = [], accumulator = 0, bits = 0
        for byte in rle {
            accumulator = (accumulator << 8) | Int(byte); bits += 8
            while bits >= 6 { bits -= 6; text.append(alphabet[(accumulator >> bits) & 63]) }
        }
        if bits > 0 { text.append(alphabet[(accumulator << (6 - bits)) & 63]) }
        var lines = Data("(This file must be converted with BinHex 4.0)\r\r:".utf8)
        for start in stride(from: 0, to: text.count, by: 64) {
            lines.append(contentsOf: text[start ..< min(start + 64, text.count)]); lines.append(0x0D)
        }
        lines.append(UInt8(ascii: ":"))
        return lines
    }

    func check(_ source: MacForkSource, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(source.displayName, "Small App", file: file, line: line)
        XCTAssertEqual(source.creator, "ORGN", file: file, line: line)
        XCTAssertEqual(source.resourceFork, Self.fork, file: file, line: line)
        XCTAssertEqual(source.dataFork, Self.dataFork, file: file, line: line)
    }

    // MARK: Single-file containers

    func testHandBuiltForkParses() throws {
        let parsed = try MacResourceFork(data: Self.fork)
        XCTAssertEqual(parsed.resources.count, 2)
        XCTAssertEqual(parsed["STR ", 128]?.name, "hello")
        XCTAssertEqual(parsed["DATA", 1]?.data, Self.payload)
        XCTAssertEqual(MacContainers.detect(Self.fork), .resourceFork(resources: 2))
        XCTAssertEqual(try MacContainers.sources(from: Self.fork, name: "x.rsrc", origin: "x.rsrc").first?.resourceFork, Self.fork)
    }

    func testMacBinary() throws {
        for version in 1 ... 3 {
            let data = Self.macBinary(version: version)
            XCTAssertEqual(MacContainers.detect(data), .macBinary(version: version))
            let sources = try MacContainers.sources(from: data, name: "small.bin", origin: "small.bin")
            XCTAssertEqual(sources.count, 1)
            check(try XCTUnwrap(sources.first))
            XCTAssertEqual(sources.first?.fileType, "APPL")
            XCTAssertEqual(sources.first?.origin, "small.bin (MacBinary)")
        }
        var damaged = Self.macBinary(version: 3); damaged[70] = UInt8(ascii: "X")   // creator changed, CRC now wrong
        XCTAssertEqual(MacContainers.detect(damaged), .unknown)
        XCTAssertEqual(MacContainers.detect(Self.macBinary(version: 3).prefix(300)), .unknown, "truncated forks are rejected")
    }

    func testAppleSingleAndAppleDouble() throws {
        let single = Self.appleSingle(magic: 0x0005_1600, includeData: true)
        XCTAssertEqual(MacContainers.detect(single), .appleSingle)
        check(try XCTUnwrap(try MacContainers.sources(from: single, name: "x", origin: "x").first))
        let double = Self.appleSingle(magic: 0x0005_1607, includeData: false)
        XCTAssertEqual(MacContainers.detect(double), .appleDouble)
        let contents = try MacContainers.parseAppleSingle(double, name: "._x")
        XCTAssertEqual(contents.resourceFork, Self.fork)
        XCTAssertEqual(contents.type, "ORDF")
        XCTAssertTrue(contents.dataFork.isEmpty)
        var bad = double; bad[26 + 12 + 8] = 0xFF                                 // entry 2 length overflows the file
        XCTAssertThrowsError(try MacContainers.parseAppleSingle(bad, name: "._x")) { XCTAssertTrue("\($0)".contains("damaged"), "\($0)") }
    }

    func testBinHex() throws {
        let hqx = Self.binHex()
        XCTAssertEqual(MacContainers.detect(hqx), .binHex)
        let sources = try MacContainers.sources(from: hqx, name: "small.hqx", origin: "small.hqx")
        check(try XCTUnwrap(sources.first))
        XCTAssertEqual(sources.first?.fileType, "APPL")
        var corrupt = [UInt8](hqx)
        let last = corrupt.count - 12
        corrupt[last] = corrupt[last] == UInt8(ascii: "A") ? UInt8(ascii: "B") : UInt8(ascii: "A")
        XCTAssertThrowsError(try MacContainers.sources(from: Data(corrupt), name: "x", origin: "x")) { XCTAssertTrue("\($0)".contains("CRC"), "\($0)") }
        XCTAssertThrowsError(try MacContainers.sources(from: hqx.prefix(hqx.count - 3), name: "x", origin: "x")) { XCTAssertTrue("\($0)".contains("truncated"), "\($0)") }
        XCTAssertEqual(MacContainers.crc16(Array("123456789".utf8)), 0x31C3)
    }

    // MARK: HFS

    func tinyImage() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "tiny-hfs", withExtension: "dsk"), "tiny-hfs.dsk missing from test bundle")
        return try Data(contentsOf: url)
    }

    func testTinyHFSVolume() throws {
        let image = try tinyImage()
        XCTAssertEqual(MacContainers.detect(image), .hfsImage(wrapper: .raw))
        let volume = try HFSVolume(data: image)
        XCTAssertEqual(volume.name, "Tiny")
        XCTAssertEqual(volume.allocationBlockSize, 512)
        XCTAssertEqual(volume.files.map { $0.path.joined(separator: ":") }, ["Desktop", "Trail:Frag", "Trail:Hello", "Trail:Notes"])
        let hello = try XCTUnwrap(volume.file(at: ["trail", "HELLO"]), "lookup is case-insensitive")
        XCTAssertEqual(hello.type, "APPL"); XCTAssertEqual(hello.creator, "TEST")
        let helloFork = try MacResourceFork(data: hello.resourceFork)
        XCTAssertEqual(helloFork["STR ", 128]?.name, "greeting")
        XCTAssertEqual(helloFork["TEXT", 1000].map { String(decoding: $0.data, as: UTF8.self) }, "Tiny HFS fixture")
        let notes = try XCTUnwrap(volume.file(at: ["Trail", "Notes"]))
        XCTAssertEqual(String(data: notes.dataFork, encoding: .macOSRoman), "Hi\r")
        XCTAssertTrue(notes.resourceFork.isEmpty)
        // "Frag" has 13 single-block extents; only three fit the catalog record, the rest come from the extents overflow tree.
        let frag = try XCTUnwrap(volume.file(at: ["Trail", "Frag"]))
        XCTAssertEqual(frag.resourceForkLength, frag.resourceFork.count)
        XCTAssertGreaterThan(frag.resourceForkLength, 6000)
        XCTAssertEqual(try MacResourceFork(data: frag.resourceFork)["DATA", 1]?.data.count, 6000)
        XCTAssertEqual(String(data: frag.dataFork, encoding: .macOSRoman), "data fork")
        XCTAssertNil(volume.file(at: ["Trail", "Missing"]))
    }

    func testDiskCopyHeaderAndRejections() throws {
        let image = try tinyImage()
        var header = Data(repeating: 0, count: 84)
        header[0] = 4; header.replaceSubrange(1 ..< 5, with: Array("Tiny".utf8))
        var sizes = Data(); sizes.appendU32(UInt32(image.count)); sizes.appendU32(0)
        header.replaceSubrange(64 ..< 72, with: sizes); header[82] = 0x01; header[83] = 0x00
        let wrapped = header + image
        XCTAssertEqual(HFSVolume.stripDiskCopyHeader(wrapped), image)
        XCTAssertNil(HFSVolume.stripDiskCopyHeader(image))
        XCTAssertEqual(MacContainers.detect(wrapped), .hfsImage(wrapper: .diskCopy42))
        let sources = try MacContainers.sources(from: wrapped, name: "Tiny.image", origin: "Tiny.image")
        XCTAssertEqual(sources.map(\.origin), ["Tiny.image:Desktop", "Tiny.image:Trail:Frag", "Tiny.image:Trail:Hello"])

        XCTAssertThrowsError(try HFSVolume(data: Data(repeating: 0, count: 4096))) { XCTAssertTrue("\($0)".hasPrefix("Not an HFS disk image"), "\($0)") }
        var plus = Data(repeating: 0, count: 4096); plus[1024] = 0x48; plus[1025] = 0x2B
        XCTAssertThrowsError(try HFSVolume(data: plus)) { XCTAssertTrue("\($0)".contains("HFS+"), "\($0)") }
        XCTAssertThrowsError(try HFSVolume(data: image.prefix(2048))) { XCTAssertTrue("\($0)".hasPrefix("Damaged HFS volume"), "\($0)") }
        XCTAssertEqual(MacContainers.detect(Data("just text".utf8)), .unknown)
    }

    // MARK: Folder walk

    func testFolderWalkFindsContainersCompanionsAndNativeForks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacContainerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.macBinary(version: 3).write(to: root.appendingPathComponent("nested/app.bin"))
        try Self.dataFork.write(to: root.appendingPathComponent("Doubled"))
        try Self.appleSingle(magic: 0x0005_1607, includeData: false, name: "Doubled").write(to: root.appendingPathComponent("._Doubled"))
        try Data("junk".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try Data("plain text".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try tinyImage().write(to: root.appendingPathComponent("Tiny.dsk"))
        let native = root.appendingPathComponent("Native")
        try Data().write(to: native)
        let nativeWritten = (try? Self.fork.write(to: URL(fileURLWithPath: native.path + "/..namedfork/rsrc"))) != nil

        // Regular entries in name order (folders recursed in place), then "._" companions.
        let sources = try MacContainers.forkSources(at: root)
        var expected = ["Tiny.dsk:Desktop", "Tiny.dsk:Trail:Frag", "Tiny.dsk:Trail:Hello", "nested/app.bin (MacBinary)", "Doubled (AppleDouble)"]
        if nativeWritten { expected.insert("Native", at: 0) }
        XCTAssertEqual(sources.map { $0.origin.replacingOccurrences(of: root.lastPathComponent + "/", with: "") }, expected)
        let doubled = try XCTUnwrap(sources.last)
        XCTAssertEqual(doubled.displayName, "Doubled")
        XCTAssertEqual(doubled.fileType, "ORDF")
        XCTAssertEqual(doubled.dataFork, Self.dataFork, "data fork comes from the sibling file")
        XCTAssertEqual(doubled.resourceFork, Self.fork)
        if nativeWritten { XCTAssertEqual(sources.first?.resourceFork, Self.fork) }
        XCTAssertEqual(try MacContainers.forkSources(at: root, maxDepth: 0).count, expected.count - 1, "depth limit skips nested/")
        XCTAssertThrowsError(try MacContainers.forkSources(at: root.appendingPathComponent("readme.txt")))
        XCTAssertEqual(MacContainers.describe(root), "Folder")
        XCTAssertEqual(MacContainers.describe(root.appendingPathComponent("nested/app.bin")), "MacBinary III")
        XCTAssertEqual(MacContainers.describe(root.appendingPathComponent("Tiny.dsk")), "HFS disk image (17K, \"Tiny\", 4 files)")
    }
}
