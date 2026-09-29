import Foundation

/// A resource fork found somewhere the user pointed us at, with enough context to
/// tell them where it came from.
struct MacForkSource {
    let displayName: String
    /// Human-readable location, e.g. "Oregon Trail Disk.image:Oregon Trail:Oregon Color".
    let origin: String
    let fileType: String?
    let creator: String?
    let dataFork: Data
    let resourceFork: Data
}

/// Turns user-selected files and folders into resource forks. Every container is
/// recognised by its content, never by extension: HFS disk images (raw, Disk Copy 4.2,
/// Apple Partition Map), MacBinary I/II/III, AppleSingle/AppleDouble, BinHex 4.0,
/// raw resource-fork dumps and files carrying a native macOS resource fork.
enum MacContainers {
    /// Files above this size are skipped (folders) or rejected (single file).
    static let maximumFileSize = 512 * 1024 * 1024

    enum Failure: Error, CustomStringConvertible {
        case tooLarge(name: String, bytes: Int)
        case unreadable(name: String, reason: String)
        case unrecognized(name: String)
        case corrupt(kind: String, name: String, reason: String)

        var description: String {
            switch self {
            case .tooLarge(let name, let bytes):
                return "\(name) is \(bytes / (1024 * 1024)) MB; files over \(MacContainers.maximumFileSize / (1024 * 1024)) MB are not read"
            case .unreadable(let name, let reason): return "Could not read \(name): \(reason)"
            case .unrecognized(let name):
                return "\(name) is not a recognised Macintosh container (HFS disk image, MacBinary, AppleSingle/AppleDouble, BinHex, or resource fork)"
            case .corrupt(let kind, let name, let reason): return "\(name) looks like \(kind) but is damaged: \(reason)"
            }
        }
    }

    /// Container kind of a file's bytes, decided from headers only.
    enum Kind: Equatable {
        case appleSingle
        case appleDouble
        case macBinary(version: Int)
        case binHex
        case hfsImage(wrapper: HFSVolume.Wrapper)
        case resourceFork(resources: Int)
        case unknown
    }

    // MARK: Entry points

    /// Every resource-fork-bearing item found at `url` (a file or a folder), in a
    /// deterministic order. Empty resource forks are skipped. A single unrecognised
    /// file throws; unrecognised files inside a folder are ignored.
    static func forkSources(at url: URL, maxDepth: Int = 4) throws -> [MacForkSource] {
        if isDirectory(url) {
            return walk(directory: url, originPrefix: url.lastPathComponent, depth: 0, maxDepth: maxDepth)
        }
        let name = url.lastPathComponent
        if name.hasPrefix("._") {
            return try appleDoubleCompanion(url, origin: name, strict: true)
        }
        return try sources(forFile: url, origin: name, strict: true)
    }

    /// Short description of what `url` holds, for logging and UI.
    static func describe(_ url: URL) -> String {
        if isDirectory(url) { return "Folder" }
        let native = nativeResourceFork(at: url)
        let data: Data
        do { data = try readFile(url) } catch { return native != nil ? "File with native resource fork" : "\(error)" }
        let content: String?
        switch detect(data) {
        case .appleSingle: content = "AppleSingle"
        case .appleDouble: content = "AppleDouble"
        case .macBinary(let version): content = version == 1 ? "MacBinary" : "MacBinary \(version == 2 ? "II" : "III")"
        case .binHex: content = "BinHex 4.0"
        case .hfsImage(let wrapper):
            var text = wrapper == .diskCopy42 ? "Disk Copy 4.2 image of an HFS volume"
                : wrapper == .partitionMap ? "Apple Partition Map image with an HFS partition" : "HFS disk image"
            if let volume = try? HFSVolume(data: data) {
                let bytes = volume.allocationBlockSize * volume.allocationBlockCount
                text += " (\(formatSize(bytes)), \"\(volume.name)\", \(volume.files.count) files)"
            }
            content = text
        case .resourceFork(let count): content = "Raw resource fork (\(count) resources)"
        case .unknown: content = nil
        }
        switch (content, native) {
        case (let text?, nil): return text
        case (let text?, _?): return text + " with native resource fork"
        case (nil, let fork?): return "File with native resource fork (\(fork.count) bytes)"
        case (nil, nil): return "Unrecognised file"
        }
    }

    /// Classifies `data` by its header bytes.
    static func detect(_ data: Data) -> Kind {
        let reader = BinaryReader(data.prefix(2048))
        if let magic = try? reader.u32(0) {
            if magic == 0x0005_1600 { return .appleSingle }
            if magic == 0x0005_1607 { return .appleDouble }
        }
        if let version = macBinaryVersion(data) { return .macBinary(version: version) }
        if binHexStart(in: data) != nil { return .binHex }
        if let located = try? HFSVolume.locate(in: data) { return .hfsImage(wrapper: located.wrapper) }
        if let fork = try? MacResourceFork(data: data), !fork.resources.isEmpty { return .resourceFork(resources: fork.resources.count) }
        return .unknown
    }

    /// Decodes one container's bytes into fork sources (no file system access).
    static func sources(from data: Data, name: String, origin: String) throws -> [MacForkSource] {
        switch detect(data) {
        case .appleSingle, .appleDouble:
            let single = try parseAppleSingle(data, name: name)
            let displayName = single.name ?? (name.hasPrefix("._") ? String(name.dropFirst(2)) : name)
            return [MacForkSource(displayName: displayName, origin: "\(origin) (AppleSingle)", fileType: single.type,
                                  creator: single.creator, dataFork: single.dataFork, resourceFork: single.resourceFork)]
                .filter { !$0.resourceFork.isEmpty }
        case .macBinary:
            return [try parseMacBinary(data, name: name, origin: "\(origin) (MacBinary)")].filter { !$0.resourceFork.isEmpty }
        case .binHex:
            return [try parseBinHex(data, name: name, origin: "\(origin) (BinHex)")].filter { !$0.resourceFork.isEmpty }
        case .hfsImage:
            let volume: HFSVolume
            do { volume = try HFSVolume(data: data) } catch { throw Failure.corrupt(kind: "an HFS disk image", name: name, reason: "\(error)") }
            return volume.files.filter { $0.resourceForkLength > 0 }.map { file in
                MacForkSource(displayName: file.name, origin: ([origin] + file.path).joined(separator: ":"),
                              fileType: file.type, creator: file.creator, dataFork: file.dataFork, resourceFork: file.resourceFork)
            }
        case .resourceFork:
            return [MacForkSource(displayName: name, origin: origin, fileType: nil, creator: nil, dataFork: Data(), resourceFork: data)]
        case .unknown:
            throw Failure.unrecognized(name: name)
        }
    }

    // MARK: File system walking

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func readFile(_ url: URL) throws -> Data {
        let name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if let size = values?.fileSize, size > maximumFileSize { throw Failure.tooLarge(name: name, bytes: size) }
        do { return try Data(contentsOf: url) } catch { throw Failure.unreadable(name: name, reason: error.localizedDescription) }
    }

    private static func walk(directory: URL, originPrefix: String, depth: Int, maxDepth: Int) -> [MacForkSource] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var results: [MacForkSource] = []
        var nativeForks: [String: Data] = [:]
        var companions: [URL] = []
        for name in directoryEntries(at: directory).sorted() {
            let entry = directory.appendingPathComponent(name)
            let values = try? entry.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { continue }
            if name.hasPrefix("._") { companions.append(entry); continue }
            if name.hasPrefix(".") || name == "Icon\r" { continue }
            let origin = "\(originPrefix)/\(name)"
            if values?.isDirectory == true {
                if depth < maxDepth { results += walk(directory: entry, originPrefix: origin, depth: depth + 1, maxDepth: maxDepth) }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            if let fork = nativeResourceFork(at: entry) { nativeForks[name] = fork }
            results += (try? sources(forFile: entry, origin: origin, strict: false)) ?? []
        }
        for companion in companions {
            let target = String(companion.lastPathComponent.dropFirst(2))
            guard let found = try? appleDoubleCompanion(companion, origin: "\(originPrefix)/\(target)", strict: false) else { continue }
            // A file copied with its fork intact and its old ._ companion would otherwise appear twice.
            results += found.filter { nativeForks[target] != $0.resourceFork }
        }
        return results
    }

    /// Directory entry names. FileManager's listings silently drop "._" AppleDouble files
    /// on Darwin, so the POSIX directory stream is used where available.
    private static func directoryEntries(at directory: URL) -> [String] {
        #if canImport(Darwin)
        guard let stream = opendir(directory.path) else { return [] }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
        #else
        return (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #endif
    }

    /// Sources for one regular file: its native resource fork (if any) plus whatever
    /// container its data fork turns out to be.
    private static func sources(forFile url: URL, origin: String, strict: Bool) throws -> [MacForkSource] {
        let name = url.lastPathComponent
        var results: [MacForkSource] = []
        let native = nativeResourceFork(at: url)
        let data: Data
        do { data = try readFile(url) } catch {
            guard let native, !strict else { throw error }
            results.append(nativeSource(name: name, origin: origin, url: url, dataFork: Data(), resourceFork: native))
            return results
        }
        if let native { results.append(nativeSource(name: name, origin: origin, url: url, dataFork: data, resourceFork: native)) }
        do {
            results += try sources(from: data, name: name, origin: origin)
        } catch {
            if strict, results.isEmpty { throw error }
        }
        return results
    }

    private static func nativeSource(name: String, origin: String, url: URL, dataFork: Data, resourceFork: Data) -> MacForkSource {
        let info = finderInfo(at: url)
        return MacForkSource(displayName: name, origin: origin, fileType: info?.type, creator: info?.creator,
                             dataFork: dataFork, resourceFork: resourceFork)
    }

    /// An AppleDouble "._name" file next to "name": the resource fork and Finder info belong
    /// to the sibling, whose contents form the data fork.
    private static func appleDoubleCompanion(_ url: URL, origin: String, strict: Bool) throws -> [MacForkSource] {
        let companionName = url.lastPathComponent
        let target = String(companionName.dropFirst(2))
        let data = try readFile(url)
        guard detect(data) == .appleDouble || detect(data) == .appleSingle else {
            if strict { throw Failure.unrecognized(name: companionName) }
            return []
        }
        let single = try parseAppleSingle(data, name: companionName)
        guard !single.resourceFork.isEmpty else { return [] }
        let sibling = url.deletingLastPathComponent().appendingPathComponent(target)
        var dataFork = single.dataFork
        if dataFork.isEmpty, !isDirectory(sibling), let bytes = try? readFile(sibling) { dataFork = bytes }
        return [MacForkSource(displayName: single.name ?? target, origin: "\(origin) (AppleDouble)", fileType: single.type,
                              creator: single.creator, dataFork: dataFork, resourceFork: single.resourceFork)]
    }

    // MARK: Native forks and Finder info

    /// The file's own resource fork via the "..namedfork/rsrc" pseudo-path (APFS/HFS+), or,
    /// on macOS, the com.apple.ResourceFork extended attribute. Nil when absent or empty.
    static func nativeResourceFork(at url: URL) -> Data? {
        let forkPath = URL(fileURLWithPath: url.path + "/..namedfork/rsrc")
        if let size = try? forkPath.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize { return nil }
        if let data = try? Data(contentsOf: forkPath), !data.isEmpty { return data }
        #if os(macOS)
        if let data = extendedAttribute("com.apple.ResourceFork", at: url), !data.isEmpty { return data }
        #endif
        return nil
    }

    /// Finder type and creator from the com.apple.FinderInfo attribute (32 bytes: fdType, fdCreator, ...).
    static func finderInfo(at url: URL) -> (type: String, creator: String)? {
        #if os(macOS)
        guard let info = extendedAttribute("com.apple.FinderInfo", at: url), info.count >= 8 else { return nil }
        let bytes = [UInt8](info.prefix(8))
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return (MacRoman.decode(bytes[0 ..< 4]), MacRoman.decode(bytes[4 ..< 8]))
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private static func extendedAttribute(_ name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0, size <= maximumFileSize else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, name, &buffer, size, 0, 0)
            guard read > 0 else { return nil }
            return Data(buffer.prefix(read))
        }
    }
    #endif

    // MARK: MacBinary

    /// MacBinary header (128 bytes): 0 zero, 1 name length (1...63), 2 name, 65 type, 69 creator,
    /// 74 zero, 82 zero, 83 data fork length, 87 resource fork length, 101 Finder flags (II),
    /// 102 'mBIN' (III), 116 unpacked length, 120 secondary header length, 122/123 writer and
    /// reader versions (129 = II, 130 = III), 124 CRC-16/XMODEM of bytes 0...123.
    /// Each fork is padded to a 128-byte boundary. Returns the version, or nil if not MacBinary.
    static func macBinaryVersion(_ data: Data) -> Int? {
        let header = BinaryReader(data.prefix(128))
        guard header.count == 128, let nameLength = try? header.u8(1), (1 ... 63).contains(nameLength),
              let z0 = try? header.u8(0), z0 == 0, let z74 = try? header.u8(74), z74 == 0,
              let z82 = try? header.u8(82), z82 == 0,
              let dataLength = try? header.u32(83), dataLength < 0x80_0000,
              let resourceLength = try? header.u32(87), resourceLength < 0x80_0000,
              let storedCRC = try? header.u16(124), let writer = try? header.u8(122),
              let signature = try? header.slice(102, 4), let secondary = try? header.u16(120) else { return nil }
        let version: Int
        if writer >= 129 || storedCRC != 0 {
            guard crc16(header.bytes[0 ..< 124]) == storedCRC else { return nil }
            version = signature == Array("mBIN".utf8) ? 3 : 2
        } else {
            // MacBinary I: bytes 101...125 are reserved and must be zero.
            guard header.bytes[101 ..< 126].allSatisfy({ $0 == 0 }) else { return nil }
            version = 1
        }
        let dataStart = 128 + padded(Int(secondary), to: 128)
        guard dataStart + padded(Int(dataLength), to: 128) + Int(resourceLength) <= data.count else { return nil }
        return version
    }

    static func parseMacBinary(_ data: Data, name: String, origin: String) throws -> MacForkSource {
        guard macBinaryVersion(data) != nil else { throw Failure.corrupt(kind: "MacBinary", name: name, reason: "header check failed") }
        let reader = BinaryReader(data)
        let displayName = try reader.pascalString(1).text
        let type = MacRoman.decode(try reader.slice(65, 4)), creator = MacRoman.decode(try reader.slice(69, 4))
        let dataLength = Int(try reader.u32(83)), resourceLength = Int(try reader.u32(87))
        let dataStart = 128 + padded(Int(try reader.u16(120)), to: 128)
        let resourceStart = dataStart + padded(dataLength, to: 128)
        return MacForkSource(displayName: displayName, origin: origin, fileType: type, creator: creator,
                             dataFork: try reader.data(dataStart, dataLength),
                             resourceFork: try reader.data(resourceStart, resourceLength))
    }

    // MARK: AppleSingle / AppleDouble

    struct AppleSingleContents {
        let name: String?
        let type: String?
        let creator: String?
        let dataFork: Data
        let resourceFork: Data
    }

    /// AppleSingle (0x00051600) and AppleDouble (0x00051607) share one layout: magic (4),
    /// version (4), filler (16), entry count (2), then (id, offset, length) u32 triples.
    /// Entry 1 = data fork, 2 = resource fork, 3 = real name, 9 = Finder info (type, creator, ...).
    static func parseAppleSingle(_ data: Data, name: String) throws -> AppleSingleContents {
        let reader = BinaryReader(data)
        let kind = (try? reader.u32(0)) == 0x0005_1600 ? "AppleSingle" : "AppleDouble"
        func fail(_ reason: String) -> Failure { Failure.corrupt(kind: kind, name: name, reason: reason) }
        guard reader.count >= 26 else { throw fail("shorter than the 26-byte header") }
        let entryCount = Int(try reader.u16(24))
        guard entryCount <= 64 else { throw fail("\(entryCount) entries is implausible") }
        var realName: String?, type: String?, creator: String?
        var dataFork = Data(), resourceFork = Data()
        for index in 0 ..< entryCount {
            let entry = 26 + index * 12
            let id = try reader.u32(entry), offset = Int(try reader.u32(entry + 4)), length = Int(try reader.u32(entry + 8))
            guard offset >= 0, length >= 0, offset + length <= reader.count else { throw fail("entry \(id) extends past the end of the file") }
            switch id {
            case 1: dataFork = try reader.data(offset, length)
            case 2: resourceFork = try reader.data(offset, length)
            case 3: realName = MacRoman.decode(try reader.slice(offset, length))
            case 9 where length >= 8:
                let info = try reader.slice(offset, 8)
                if info.contains(where: { $0 != 0 }) { type = MacRoman.decode(info[0 ..< 4]); creator = MacRoman.decode(info[4 ..< 8]) }
            default: break
            }
        }
        return AppleSingleContents(name: realName, type: type, creator: creator, dataFork: dataFork, resourceFork: resourceFork)
    }

    // MARK: BinHex 4.0

    private static let binHexBanner = Array("(This file must be converted with BinHex".utf8)
    private static let binHexAlphabet = Array("!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8)
    private static let binHexValues: [Int8] = {
        var table = [Int8](repeating: -1, count: 256)
        for (value, character) in binHexAlphabet.enumerated() { table[Int(character)] = Int8(value) }
        return table
    }()

    /// Offset of the ':' that opens the encoded stream, after the banner line.
    /// Files whose first non-blank byte is ':' followed by a full line of alphabet
    /// characters are accepted too (the banner is occasionally stripped).
    private static func binHexStart(in data: Data) -> Int? {
        let head = [UInt8](data.prefix(16 * 1024))
        if let banner = firstRange(of: binHexBanner, in: head) {
            return head[banner...].firstIndex(of: UInt8(ascii: ":"))
        }
        guard let first = head.firstIndex(where: { $0 != 0x0D && $0 != 0x0A && $0 != 0x20 && $0 != 0x09 }),
              head[first] == UInt8(ascii: ":"), head.count > first + 60,
              head[(first + 1) ..< (first + 60)].allSatisfy({ binHexValues[Int($0)] >= 0 }) else { return nil }
        return first
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        return (0 ... haystack.count - needle.count).first { haystack[$0 ..< $0 + needle.count].elementsEqual(needle) }
    }

    /// Text between the two ':' markers is a 6-bit encoding (alphabet above) of an RLE90
    /// stream. Decoded: name (Pascal), version (1), type (4), creator (4), flags (2), data
    /// length (4), resource length (4), CRC (2); then data fork + CRC, resource fork + CRC.
    /// CRCs are CRC-16/XMODEM (poly 0x1021, init 0) over the preceding section.
    static func parseBinHex(_ data: Data, name: String, origin: String) throws -> MacForkSource {
        func fail(_ reason: String) -> Failure { Failure.corrupt(kind: "BinHex 4.0", name: name, reason: reason) }
        guard let start = binHexStart(in: data) else { throw fail("no ':' after the BinHex banner") }
        let bytes = [UInt8](data)
        var packed: [UInt8] = []
        var accumulator: UInt32 = 0, bits = 0, terminated = false
        for byte in bytes[(start + 1)...] {
            if byte == UInt8(ascii: ":") { terminated = true; break }
            if byte == 0x0D || byte == 0x0A || byte == 0x20 || byte == 0x09 { continue }
            let value = binHexValues[Int(byte)]
            guard value >= 0 else { throw fail("character '\(Character(UnicodeScalar(byte)))' is not in the BinHex alphabet") }
            accumulator = (accumulator << 6) | UInt32(value); bits += 6
            if bits >= 8 { bits -= 8; packed.append(UInt8((accumulator >> UInt32(bits)) & 0xFF)) }
        }
        guard terminated else { throw fail("the closing ':' is missing; the file is truncated") }
        // RLE90: 0x90 n repeats the previous byte n-1 more times; 0x90 0x00 is a literal 0x90.
        var stream: [UInt8] = []
        stream.reserveCapacity(packed.count)
        var index = 0
        while index < packed.count {
            let byte = packed[index]; index += 1
            if byte == 0x90, index < packed.count {
                let count = Int(packed[index]); index += 1
                if count == 0 { stream.append(0x90) } else if let last = stream.last { stream.append(contentsOf: repeatElement(last, count: count - 1)) }
            } else {
                stream.append(byte)
            }
        }
        let reader = BinaryReader(bytes: stream)
        do {
            let nameLength = Int(try reader.u8(0))
            let headerLength = 1 + nameLength + 1 + 4 + 4 + 2 + 4 + 4
            let displayName = MacRoman.decode(try reader.slice(1, nameLength))
            let type = MacRoman.decode(try reader.slice(1 + nameLength + 1, 4))
            let creator = MacRoman.decode(try reader.slice(1 + nameLength + 5, 4))
            let dataLength = Int(try reader.u32(1 + nameLength + 11)), resourceLength = Int(try reader.u32(1 + nameLength + 15))
            guard try reader.u16(headerLength) == crc16(stream[0 ..< headerLength]) else { throw fail("header CRC mismatch") }
            let dataStart = headerLength + 2
            let dataFork = try reader.slice(dataStart, dataLength)
            guard try reader.u16(dataStart + dataLength) == crc16(dataFork[...]) else { throw fail("data fork CRC mismatch") }
            let resourceStart = dataStart + dataLength + 2
            let resourceFork = try reader.slice(resourceStart, resourceLength)
            guard try reader.u16(resourceStart + resourceLength) == crc16(resourceFork[...]) else { throw fail("resource fork CRC mismatch") }
            return MacForkSource(displayName: displayName, origin: origin, fileType: type, creator: creator,
                                 dataFork: Data(dataFork), resourceFork: Data(resourceFork))
        } catch let failure as BinaryReader.Failure {
            throw fail("decoded stream is too short (\(failure))")
        }
    }

    // MARK: Helpers

    /// CRC-16/XMODEM (polynomial 0x1021, initial value 0, no reflection), as used by
    /// MacBinary II/III and BinHex 4.0.
    static func crc16<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }

    private static func padded(_ value: Int, to multiple: Int) -> Int { (value + multiple - 1) / multiple * multiple }

    private static func formatSize(_ bytes: Int) -> String {
        bytes < 4 * 1024 * 1024 ? "\(bytes / 1024)K" : String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
