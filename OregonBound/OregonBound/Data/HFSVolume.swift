import Foundation

/// Read-only reader for HFS Standard volumes (signature 'BD'), the file system of
/// 400K/800K/1.4M floppies and pre-1998 Macintosh hard disks
/// (Inside Macintosh: Files, chapter 2 "Data Organization on Volumes").
/// HFS+ ('H+') volumes are rejected with a clear error.
///
/// The image bytes are never copied as a whole: forks are materialised on demand
/// from the shared image, so `files` is cheap even for a few hundred MB image.
struct HFSVolume {
    enum Failure: Error, CustomStringConvertible {
        case notHFS(String)
        case hfsPlus(String)
        case partitioned(String)
        case corrupt(String)

        var description: String {
            switch self {
            case .notHFS(let reason): return "Not an HFS disk image: \(reason)"
            case .hfsPlus(let reason): return "Unsupported HFS+ (Mac OS Extended) volume: \(reason)"
            case .partitioned(let reason): return "Partitioned disk image: \(reason)"
            case .corrupt(let reason): return "Damaged HFS volume: \(reason)"
            }
        }
    }

    /// How the HFS volume was found inside the bytes handed to `locate(in:)`.
    enum Wrapper: Equatable { case raw, diskCopy42, partitionMap }

    /// One allocation-block run: `count` blocks starting at block `start`.
    struct Extent: Equatable { let start: Int; let count: Int }

    struct File {
        let name: String
        /// Folder names from the volume root, ending with `name` (volume name excluded).
        let path: [String]
        let type: String
        let creator: String
        let cnid: UInt32
        let dataForkLength: Int
        let resourceForkLength: Int
        fileprivate let storage: Storage
        fileprivate let dataExtents: [Extent]
        fileprivate let resourceExtents: [Extent]

        /// Fork contents, copied out of the image on each access (indices start at 0).
        var dataFork: Data { storage.read(dataExtents, length: dataForkLength) }
        var resourceFork: Data { storage.read(resourceExtents, length: resourceForkLength) }
    }

    let name: String
    /// Allocation block size in bytes and the number of allocation blocks.
    let allocationBlockSize: Int
    let allocationBlockCount: Int
    /// Every file, depth-first from the root, folders' children in catalog (name) order.
    let files: [File]

    /// Parses a raw HFS volume; also accepts a Disk Copy 4.2 container or an
    /// Apple Partition Map image holding a single Apple_HFS partition.
    init(data: Data) throws {
        guard let located = try HFSVolume.locate(in: data) else {
            if data.count >= 1536, data[data.startIndex + 1024] == 0x48,
               [0x2B, 0x58].contains(data[data.startIndex + 1025]) {   // 'H+' / 'HX' at byte 1024
                throw Failure.hfsPlus("'\(MacRoman.decode(data[data.startIndex + 1024 ..< data.startIndex + 1026]))' signature at byte 1024")
            }
            throw Failure.notHFS("no 'BD' signature at byte 1024 (raw, Disk Copy 4.2 or partitioned)")
        }
        try self.init(rawVolume: located.data)
    }

    private init(rawVolume image: Data) throws {
        let base = image.startIndex
        guard image.count >= 1536 else { throw Failure.notHFS("shorter than boot blocks plus Master Directory Block") }
        // Master Directory Block: logical block 2 (byte 1024), 512 bytes.
        let mdb = BinaryReader(image[base + 1024 ..< base + 1536])
        let signature = try mdb.u16(0)
        guard signature == 0x4244 else {
            if signature == 0x482B { throw Failure.hfsPlus("'H+' signature at byte 1024") }
            throw Failure.notHFS("no 'BD' signature at byte 1024")
        }
        // drEmbedSigWord (offset 0x7C, overlaying drVCSize): an HFS wrapper around an HFS+ volume.
        if try mdb.u16(0x7C) == 0x482B { throw Failure.hfsPlus("HFS wrapper volume; the files live in the embedded HFS+ volume") }

        let blockCount = Int(try mdb.u16(18))          // drNmAlBlks
        let blockSize = Int(try mdb.u32(20))           // drAlBlkSiz
        let firstBlock = Int(try mdb.u16(28))          // drAlBlSt, in 512-byte logical blocks
        let volumeName = try mdb.pascalString(36).text // drVN, up to 27 characters
        guard blockSize > 0, blockSize % 512 == 0, blockSize <= 64 * 1024 * 1024 else {
            throw Failure.corrupt("allocation block size \(blockSize) is not a multiple of 512")
        }
        guard blockCount > 0 else { throw Failure.corrupt("volume has no allocation blocks") }
        let storage = Storage(image: image, allocationBase: firstBlock * 512, blockSize: blockSize, blockCount: blockCount)
        name = volumeName
        allocationBlockSize = blockSize
        allocationBlockCount = blockCount

        // Extents overflow file (CNID 3): extra extent records for fragmented forks.
        let overflowLength = Int(try mdb.u32(130))                          // drXTFlSize
        let overflowExtents = try storage.extents(try mdb.slice(134, 12))   // drXTExtRec
        var overflow: [OverflowKey: [Extent]] = [:]
        if overflowLength > 0 {
            let tree = try BTree(storage.read(overflowExtents, length: overflowLength), label: "extents overflow")
            try tree.forEachLeafRecord { reader, record, keyLength, valueOffset in
                // Key: xkrKeyLen, xkrFkType (0 data / 0xFF resource), xkrFNum, xkrFABN.
                guard keyLength >= 7 else { return }
                let key = OverflowKey(forkType: try reader.u8(record + 1), cnid: try reader.u32(record + 2),
                                      firstBlock: Int(try reader.u16(record + 6)))
                overflow[key] = try storage.extents(try reader.slice(valueOffset, 12))
            }
        }
        let fork = { (length: Int, record: [UInt8], cnid: UInt32, forkType: UInt8) throws -> [Extent] in
            try storage.allExtents(length: length, first: record, cnid: cnid, forkType: forkType, overflow: overflow)
        }

        // Catalog file (CNID 4): one leaf record per folder, file and thread.
        let catalogLength = Int(try mdb.u32(146))                                                   // drCTFlSize
        let catalogExtents = try fork(catalogLength, try mdb.slice(150, 12), 4, 0)                  // drCTExtRec
        guard catalogLength > 0 else { throw Failure.corrupt("catalog file is empty") }
        let catalog = try BTree(storage.read(catalogExtents, length: catalogLength), label: "catalog")

        struct Folder { let name: String; let parent: UInt32 }
        enum Child { case folder(UInt32); case file(File) }
        var folders: [UInt32: Folder] = [2: Folder(name: volumeName, parent: 1)]
        var children: [UInt32: [Child]] = [:]
        try catalog.forEachLeafRecord { reader, record, keyLength, valueOffset in
            // Key: ckrKeyLen, ckrResrv1, ckrParID (4), ckrCName (Pascal string).
            guard keyLength >= 6 else { return }
            let parent = try reader.u32(record + 2)
            let nameLength = min(Int(try reader.u8(record + 6)), keyLength - 6)
            let childName = MacRoman.decode(try reader.slice(record + 7, nameLength))
            let v = valueOffset
            switch try reader.u8(v) {                     // cdrType
            case 1:                                       // directory record
                let id = try reader.u32(v + 6)            // dirDirID
                folders[id] = Folder(name: childName, parent: parent)
                children[parent, default: []].append(.folder(id))
            case 2:                                       // file record
                let cnid = try reader.u32(v + 20)         // filFlNum
                let dataLength = Int(try reader.u32(v + 26))      // filLgLen
                let resourceLength = Int(try reader.u32(v + 36))  // filRLgLen
                let file = File(
                    name: childName, path: [], // path is filled in during the walk below
                    type: MacRoman.decode(try reader.slice(v + 4, 4)),     // filUsrWds.fdType
                    creator: MacRoman.decode(try reader.slice(v + 8, 4)),  // filUsrWds.fdCreator
                    cnid: cnid, dataForkLength: dataLength, resourceForkLength: resourceLength,
                    storage: storage,
                    dataExtents: try fork(dataLength, try reader.slice(v + 74, 12), cnid, 0),          // filExtRec
                    resourceExtents: try fork(resourceLength, try reader.slice(v + 86, 12), cnid, 0xFF)) // filRExtRec
                children[parent, default: []].append(.file(file))
            default:                                      // thread records (3, 4) carry no new facts
                break
            }
        }

        // Depth-first walk from the root folder (CNID 2, whose parent is the pseudo-folder 1).
        var files: [File] = []
        var visited: Set<UInt32> = []
        func walk(_ folder: UInt32, _ prefix: [String]) {
            guard visited.insert(folder).inserted else { return }
            for child in children[folder] ?? [] {
                switch child {
                case .folder(let id):
                    if let info = folders[id] { walk(id, prefix + [info.name]) }
                case .file(let file):
                    files.append(File(name: file.name, path: prefix + [file.name], type: file.type, creator: file.creator,
                                      cnid: file.cnid, dataForkLength: file.dataForkLength,
                                      resourceForkLength: file.resourceForkLength, storage: storage,
                                      dataExtents: file.dataExtents, resourceExtents: file.resourceExtents))
                }
            }
        }
        walk(2, [])
        self.files = files
    }

    /// Looks a file up by path components using HFS's case-insensitive name comparison.
    func file(at path: [String]) -> File? {
        files.first { candidate in
            candidate.path.count == path.count
                && zip(candidate.path, path).allSatisfy { HFSVolume.namesEqual($0, $1) }
        }
    }

    // MARK: Container detection

    /// Finds the HFS volume bytes in a raw image, a Disk Copy 4.2 container, or an
    /// Apple Partition Map image. Returns nil when no 'BD' signature is found;
    /// throws when a partition map exists but holds no HFS partition.
    static func locate(in data: Data) throws -> (data: Data, wrapper: Wrapper)? {
        if hasSignature(data) { return (data, .raw) }
        if let stripped = stripDiskCopyHeader(data), hasSignature(stripped) { return (stripped, .diskCopy42) }
        if let partition = try hfsPartition(in: data) { return (partition, .partitionMap) }
        return nil
    }

    static func hasSignature(_ data: Data) -> Bool {
        guard data.count >= 1536 else { return false }
        let i = data.startIndex + 1024
        return data[i] == 0x42 && data[i + 1] == 0x44
    }

    /// Disk Copy 4.2 header (84 bytes): Pascal name (64), data size (BE u32 at 64),
    /// tag size (68), data checksum (72), tag checksum (76), disk format (80),
    /// format byte (81), magic 0x0100 (82). Image data follows at byte 84.
    static func stripDiskCopyHeader(_ data: Data) -> Data? {
        guard data.count >= 84 + 1536 else { return nil }
        let reader = BinaryReader(data.prefix(84))
        guard let nameLength = try? reader.u8(0), nameLength <= 63,
              let dataSize = try? reader.u32(64), let tagSize = try? reader.u32(68),
              let magic = try? reader.u16(82), magic == 0x0100,
              dataSize % 512 == 0, dataSize > 0,
              Int(dataSize) + Int(tagSize) + 84 <= data.count else { return nil }
        let start = data.startIndex + 84
        return data[start ..< start + Int(dataSize)]
    }

    /// Apple Partition Map: block 0 may hold a Driver Descriptor ('ER'); blocks 1... hold
    /// 512-byte partition entries signed 'PM' with pmMapBlkCnt (4), pmPyPartStart (8),
    /// pmPartBlkCnt (12), pmPartName (16, 32 bytes), pmParType (48, 32 bytes).
    static func hfsPartition(in data: Data) throws -> Data? {
        guard data.count >= 1024 else { return nil }
        let base = data.startIndex
        let first = BinaryReader(data[base + 512 ..< base + 1024])
        guard try first.u16(0) == 0x504D else { return nil }
        let mapEntries = min(Int(try first.u32(4)), 256)
        var seen: [String] = []
        for index in 0 ..< max(mapEntries, 1) {
            let offset = base + 512 * (1 + index)
            guard offset + 512 <= data.endIndex else { break }
            let entry = BinaryReader(data[offset ..< offset + 512])
            guard try entry.u16(0) == 0x504D else { break }
            let typeBytes = try entry.slice(48, 32).prefix { $0 != 0 }
            let type = MacRoman.decode(typeBytes)
            seen.append(type)
            guard type == "Apple_HFS" else { continue }
            let start = Int(try entry.u32(8)) * 512
            let length = Int(try entry.u32(12)) * 512
            guard start >= 0, length > 0, start + length <= data.count else {
                throw Failure.partitioned("Apple_HFS partition extends past the end of the image")
            }
            let slice = data[base + start ..< base + start + length]
            if hasSignature(slice) { return slice }
            throw Failure.partitioned("the Apple_HFS partition does not contain an HFS volume (probably HFS+)")
        }
        throw Failure.partitioned("no Apple_HFS partition found (partition types: \(seen.joined(separator: ", ")))")
    }

    // MARK: Name comparison

    /// HFS compares names case-insensitively through a fixed Mac Roman collation table
    /// (the Finder's RelString table); letters of both cases share a weight.
    static func namesEqual(_ a: String, _ b: String) -> Bool {
        guard let x = MacRoman.encode(a), let y = MacRoman.encode(b) else {
            return a.caseInsensitiveCompare(b) == .orderedSame
        }
        return x.count == y.count && zip(x, y).allSatisfy { collation[Int($0)] == collation[Int($1)] }
    }

    private static let collation: [UInt8] = [
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
        0x20, 0x22, 0x23, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
        0x47, 0x48, 0x58, 0x5a, 0x5e, 0x60, 0x67, 0x69, 0x6b, 0x6d, 0x73, 0x75, 0x77, 0x79, 0x7b, 0x7f,
        0x8d, 0x8f, 0x91, 0x93, 0x96, 0x98, 0x9f, 0xa1, 0xa3, 0xa5, 0xa8, 0xaa, 0xab, 0xac, 0xad, 0xae,
        0x54, 0x48, 0x58, 0x5a, 0x5e, 0x60, 0x67, 0x69, 0x6b, 0x6d, 0x73, 0x75, 0x77, 0x79, 0x7b, 0x7f,
        0x8d, 0x8f, 0x91, 0x93, 0x96, 0x98, 0x9f, 0xa1, 0xa3, 0xa5, 0xa8, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3,
        0x4c, 0x50, 0x5c, 0x62, 0x7d, 0x81, 0x9a, 0x55, 0x4a, 0x56, 0x4c, 0x4e, 0x50, 0x5c, 0x62, 0x64,
        0x65, 0x66, 0x6f, 0x70, 0x71, 0x72, 0x7d, 0x89, 0x8a, 0x8b, 0x81, 0x83, 0x9c, 0x9d, 0x9e, 0x9a,
        0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0x95, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0x52, 0x85,
        0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0x57, 0x8c, 0xcc, 0x52, 0x85,
        0xcd, 0xce, 0xcf, 0xd0, 0xd1, 0xd2, 0xd3, 0x26, 0x27, 0xd4, 0x20, 0x4a, 0x4e, 0x83, 0x87, 0x87,
        0xd5, 0xd6, 0x24, 0x25, 0x2d, 0x2e, 0xd7, 0xd8, 0xa7, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf,
        0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef,
        0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
    ]

    // MARK: Storage

    fileprivate struct OverflowKey: Hashable { let forkType: UInt8; let cnid: UInt32; let firstBlock: Int }

    /// The shared image plus the geometry needed to turn allocation blocks into bytes.
    fileprivate final class Storage {
        let image: Data
        let allocationBase: Int   // byte offset of allocation block 0 (drAlBlSt * 512)
        let blockSize: Int
        let blockCount: Int

        init(image: Data, allocationBase: Int, blockSize: Int, blockCount: Int) {
            self.image = image; self.allocationBase = allocationBase
            self.blockSize = blockSize; self.blockCount = blockCount
        }

        /// Decodes a 12-byte extent record (three (start, count) pairs), checking bounds.
        func extents(_ record: [UInt8]) throws -> [Extent] {
            let reader = BinaryReader(bytes: record)
            var result: [Extent] = []
            for pair in 0 ..< 3 {
                let start = Int(try reader.u16(pair * 4)), count = Int(try reader.u16(pair * 4 + 2))
                guard count > 0 else { continue }
                guard start + count <= blockCount,
                      allocationBase + (start + count) * blockSize <= image.count else {
                    throw Failure.corrupt("extent \(start)+\(count) lies outside the \(blockCount)-block volume")
                }
                result.append(Extent(start: start, count: count))
            }
            return result
        }

        /// The first three extents live in the catalog record; further ones are keyed in the
        /// extents overflow tree by (fork, CNID, first file block covered by that record).
        func allExtents(length: Int, first: [UInt8], cnid: UInt32, forkType: UInt8,
                        overflow: [OverflowKey: [Extent]]) throws -> [Extent] {
            let needed = (length + blockSize - 1) / blockSize
            var result = try extents(first)
            var covered = result.reduce(0) { $0 + $1.count }
            while covered < needed {
                guard let more = overflow[OverflowKey(forkType: forkType, cnid: cnid, firstBlock: covered)],
                      !more.isEmpty else {
                    throw Failure.corrupt("file #\(cnid) needs \(needed) blocks but only \(covered) are recorded")
                }
                result += more
                covered += more.reduce(0) { $0 + $1.count }
            }
            return result
        }

        /// Concatenates the bytes of `extents`, truncated to the fork's logical length.
        func read(_ extents: [Extent], length: Int) -> Data {
            var out = Data(capacity: length)
            var remaining = length
            for extent in extents where remaining > 0 {
                let offset = image.startIndex + allocationBase + extent.start * blockSize
                let count = min(extent.count * blockSize, remaining, max(0, image.endIndex - offset))
                guard count > 0 else { break }
                out.append(image[offset ..< offset + count])
                remaining -= count
            }
            return out
        }
    }

    // MARK: B*-tree

    /// HFS B*-tree with 512-byte nodes. Node descriptor: ndFLink (4), ndBLink (4), ndType (1:
    /// 0 index, 1 header, 2 map, 0xFF leaf), ndNHeight (1), ndNRecs (2). Record offsets are
    /// u16s growing backwards from the end of the node; the header record of node 0 holds
    /// bthDepth (2), bthRoot (4), bthNRecs (4), bthFNode (4), bthLNode (4), bthNodeSize (2) ...
    private struct BTree {
        static let nodeSize = 512
        let reader: BinaryReader
        let label: String
        let nodeCount: Int
        let firstLeaf: Int
        let lastLeaf: Int

        init(_ data: Data, label: String) throws {
            reader = BinaryReader(data)
            self.label = label
            nodeCount = reader.count / BTree.nodeSize
            guard nodeCount >= 1, try reader.u8(8) == 1 else { throw Failure.corrupt("\(label) B-tree has no header node") }
            let header = Int(try reader.u16(BTree.nodeSize - 2))
            guard header >= 14, header + 30 <= BTree.nodeSize - 8 else { throw Failure.corrupt("\(label) B-tree header record is misplaced") }
            firstLeaf = Int(try reader.u32(header + 10))
            lastLeaf = Int(try reader.u32(header + 14))
            let nodeSize = Int(try reader.u16(header + 18))
            guard nodeSize == BTree.nodeSize else { throw Failure.corrupt("\(label) B-tree uses \(nodeSize)-byte nodes; HFS requires 512") }
        }

        /// Visits every leaf record following the leaf chain from bthFNode via ndFLink.
        /// `body` receives the record start (key length byte), the key length, and the offset
        /// of the record data (key padded to an even length).
        func forEachLeafRecord(_ body: (_ reader: BinaryReader, _ record: Int, _ keyLength: Int, _ valueOffset: Int) throws -> Void) throws {
            var node = firstLeaf
            var visited: Set<Int> = []
            while node != 0 {
                guard node < nodeCount, visited.insert(node).inserted else {
                    throw Failure.corrupt("\(label) B-tree leaf chain points to node \(node) of \(nodeCount)")
                }
                let base = node * BTree.nodeSize
                guard try reader.u8(base + 8) == 0xFF else { throw Failure.corrupt("\(label) B-tree node \(node) is not a leaf") }
                let records = Int(try reader.u16(base + 10))
                for index in 0 ..< records {
                    let start = base + Int(try reader.u16(base + BTree.nodeSize - 2 * (index + 1)))
                    let end = base + Int(try reader.u16(base + BTree.nodeSize - 2 * (index + 2)))
                    guard start >= base + 14, end <= base + BTree.nodeSize, start < end else {
                        throw Failure.corrupt("\(label) B-tree node \(node) record \(index) has bad offsets")
                    }
                    let keyLength = Int(try reader.u8(start))
                    guard keyLength > 0 else { continue }               // deleted / empty key
                    let valueOffset = start + (1 + keyLength + 1) / 2 * 2
                    guard valueOffset <= end else { continue }
                    try body(reader, start, keyLength, valueOffset)
                }
                if node == lastLeaf { break }
                node = Int(try reader.u32(base))                      // ndFLink
            }
        }
    }
}
