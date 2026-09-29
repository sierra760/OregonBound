import CryptoKit
import Foundation

/// Expands System 7 compressed resources (resource attribute bit 0 set).
///
/// Only the 'dcmp' 2 "GreggyBits" scheme used by the System 7.0 System file is
/// implemented, following macresources' `greggybits.unpack` exactly: an 18-byte
/// header, an optional dynamic word table, either a bitmapped stream (one mask
/// byte per eight output words selecting table lookups versus literal words) or a
/// table-only stream, and an optional trailing odd byte copied verbatim.
enum SystemResourceDecompressor {
    enum Failure: Error, CustomStringConvertible {
        case tooShort(type: String, id: Int, length: Int)
        case badMagic(type: String, id: Int, found: UInt32)
        case unsupportedDecompressor(type: String, id: Int, dcmp: Int)
        case malformedHeader(type: String, id: Int, reason: String)
        case truncated(type: String, id: Int, at: Int)
        case tableIndexOutOfRange(type: String, id: Int, index: Int, tableSize: Int)

        var description: String {
            switch self {
            case .tooShort(let type, let id, let length):
                return "Compressed resource '\(type)' \(id) is only \(length) bytes; the System 7 compression header needs 18"
            case .badMagic(let type, let id, let found):
                return "Compressed resource '\(type)' \(id) does not start with the System 7 compression signature (found 0x\(String(found, radix: 16, uppercase: true)))"
            case .unsupportedDecompressor(let type, let id, let dcmp):
                return "Compressed resource '\(type)' \(id) uses decompressor 'dcmp' \(dcmp); only 'dcmp' 2 (GreggyBits) from System 7.0 is supported"
            case .malformedHeader(let type, let id, let reason):
                return "Compressed resource '\(type)' \(id) has a malformed compression header: \(reason)"
            case .truncated(let type, let id, let at):
                return "Compressed resource '\(type)' \(id) ends prematurely at byte \(at)"
            case .tableIndexOutOfRange(let type, let id, let index, let tableSize):
                return "Compressed resource '\(type)' \(id) references word-table entry \(index) but the table has \(tableSize) entries"
            }
        }
    }

    static let signature: UInt32 = 0xA89F6572

    /// Returns the resource payload, expanded when the resource is compressed.
    static func expand(_ resource: MacResource) throws -> Data {
        guard resource.isCompressed else { return resource.data }
        return try unpackGreggyBits(resource.data, type: resource.type, id: resource.id)
    }

    /// Port of `macresources.greggybits.unpack`; `type`/`id` only label errors.
    static func unpackGreggyBits(_ source: Data, type: String = "", id: Int = 0) throws -> Data {
        let reader = BinaryReader(source)
        guard reader.count >= 18 else { throw Failure.tooShort(type: type, id: id, length: reader.count) }
        let magic = try reader.u32(0)
        guard magic == signature else { throw Failure.badMagic(type: type, id: id, found: magic) }
        let headerLength = try reader.u16(4)
        let version = try reader.u8(6)
        let isCompressed = try reader.u8(7)
        let unpackSize = Int(try reader.u32(8))
        let decompressorID = Int(try reader.i16(12))
        // Bytes 14-15 hold the "slop" working-space hint; unused when expanding.
        let tableSize = Int(try reader.u8(16))
        let flags = try reader.u8(17)
        guard decompressorID == 2 else { throw Failure.unsupportedDecompressor(type: type, id: id, dcmp: decompressorID) }
        guard headerLength == 18 else { throw Failure.malformedHeader(type: type, id: id, reason: "header length \(headerLength) is not 18") }
        guard version == 9 else { throw Failure.malformedHeader(type: type, id: id, reason: "header version \(version) is not 9") }
        guard isCompressed == 1 else { throw Failure.malformedHeader(type: type, id: id, reason: "compression flag \(isCompressed) is not 1") }

        let hasDynamicTable = flags & 1 != 0
        let isBitmapped = flags & 2 != 0
        var position = 18

        var table: [(UInt8, UInt8)]
        if hasDynamicTable {
            let entryCount = tableSize + 1
            table = []
            table.reserveCapacity(entryCount)
            for _ in 0..<entryCount {
                guard position + 2 <= reader.count else { throw Failure.truncated(type: type, id: id, at: position) }
                table.append((reader.bytes[position], reader.bytes[position + 1]))
                position += 2
            }
        } else {
            table = staticTable.map { (UInt8($0 >> 8), UInt8($0 & 0xff)) }
        }

        var output = [UInt8]()
        output.reserveCapacity(unpackSize)
        let evenLength = unpackSize - (unpackSize % 2)

        func byte() throws -> UInt8 {
            guard position < reader.count else { throw Failure.truncated(type: type, id: id, at: position) }
            let value = reader.bytes[position]
            position += 1
            return value
        }
        func appendTableWord(_ index: UInt8) throws {
            guard Int(index) < table.count else {
                throw Failure.tableIndexOutOfRange(type: type, id: id, index: Int(index), tableSize: table.count)
            }
            let word = table[Int(index)]
            output.append(word.0)
            output.append(word.1)
        }

        if isBitmapped {
            var mask: UInt8 = 0
            while output.count < evenLength {
                if output.count & 0xF == 0 { mask = try byte() }
                if mask & 0x80 != 0 {
                    try appendTableWord(try byte())
                } else {
                    output.append(try byte())
                    output.append(try byte())
                }
                mask = mask << 1
            }
        } else {
            while output.count < evenLength {
                try appendTableWord(try byte())
            }
        }
        if unpackSize & 1 != 0 {
            output.append(try byte())
        }
        return Data(output)
    }

    /// Predefined table of the most frequent 68k words (macresources.greggybits.TABLE).
    static let staticTable: [UInt16] = [
        0x0000, 0x0008, 0x4EBA, 0x206E, 0x4E75, 0x000C, 0x0004, 0x7000,
        0x0010, 0x0002, 0x486E, 0xFFFC, 0x6000, 0x0001, 0x48E7, 0x2F2E,
        0x4E56, 0x0006, 0x4E5E, 0x2F00, 0x6100, 0xFFF8, 0x2F0B, 0xFFFF,
        0x0014, 0x000A, 0x0018, 0x205F, 0x000E, 0x2050, 0x3F3C, 0xFFF4,
        0x4CEE, 0x302E, 0x6700, 0x4CDF, 0x266E, 0x0012, 0x001C, 0x4267,
        0xFFF0, 0x303C, 0x2F0C, 0x0003, 0x4ED0, 0x0020, 0x7001, 0x0016,
        0x2D40, 0x48C0, 0x2078, 0x7200, 0x588F, 0x6600, 0x4FEF, 0x42A7,
        0x6706, 0xFFFA, 0x558F, 0x286E, 0x3F00, 0xFFFE, 0x2F3C, 0x6704,
        0x598F, 0x206B, 0x0024, 0x201F, 0x41FA, 0x81E1, 0x6604, 0x6708,
        0x001A, 0x4EB9, 0x508F, 0x202E, 0x0007, 0x4EB0, 0xFFF2, 0x3D40,
        0x001E, 0x2068, 0x6606, 0xFFF6, 0x4EF9, 0x0800, 0x0C40, 0x3D7C,
        0xFFEC, 0x0005, 0x203C, 0xFFE8, 0xDEFC, 0x4A2E, 0x0030, 0x0028,
        0x2F08, 0x200B, 0x6002, 0x426E, 0x2D48, 0x2053, 0x2040, 0x1800,
        0x6004, 0x41EE, 0x2F28, 0x2F01, 0x670A, 0x4840, 0x2007, 0x6608,
        0x0118, 0x2F07, 0x3028, 0x3F2E, 0x302B, 0x226E, 0x2F2B, 0x002C,
        0x670C, 0x225F, 0x6006, 0x00FF, 0x3007, 0xFFEE, 0x5340, 0x0040,
        0xFFE4, 0x4A40, 0x660A, 0x000F, 0x4EAD, 0x70FF, 0x22D8, 0x486B,
        0x0022, 0x204B, 0x670E, 0x4AAE, 0x4E90, 0xFFE0, 0xFFC0, 0x002A,
        0x2740, 0x6702, 0x51C8, 0x02B6, 0x487A, 0x2278, 0xB06E, 0xFFE6,
        0x0009, 0x322E, 0x3E00, 0x4841, 0xFFEA, 0x43EE, 0x4E71, 0x7400,
        0x2F2C, 0x206C, 0x003C, 0x0026, 0x0050, 0x1880, 0x301F, 0x2200,
        0x660C, 0xFFDA, 0x0038, 0x6602, 0x302C, 0x200C, 0x2D6E, 0x4240,
        0xFFE2, 0xA9F0, 0xFF00, 0x377C, 0xE580, 0xFFDC, 0x4868, 0x594F,
        0x0034, 0x3E1F, 0x6008, 0x2F06, 0xFFDE, 0x600A, 0x7002, 0x0032,
        0xFFCC, 0x0080, 0x2251, 0x101F, 0x317C, 0xA029, 0xFFD8, 0x5240,
        0x0100, 0x6710, 0xA023, 0xFFCE, 0xFFD4, 0x2006, 0x4878, 0x002E,
        0x504F, 0x43FA, 0x6712, 0x7600, 0x41E8, 0x4A6E, 0x20D9, 0x005A,
        0x7FFF, 0x51CA, 0x005C, 0x2E00, 0x0240, 0x48C7, 0x6714, 0x0C80,
        0x2E9F, 0xFFD6, 0x8000, 0x1000, 0x4842, 0x4A6B, 0xFFD2, 0x0048,
        0x4A47, 0x4ED1, 0x206F, 0x0041, 0x600C, 0x2A78, 0x422E, 0x3200,
        0x6574, 0x6716, 0x0044, 0x486D, 0x2008, 0x486C, 0x0B7C, 0x2640,
        0x0400, 0x0068, 0x206D, 0x000D, 0x2A40, 0x000B, 0x003E, 0x0220,
    ]
}

/// Lower-case hex SHA-256, matching Python's `hashlib.sha256(...).hexdigest()`.
enum SHA256Hex {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Provenance of the verified System 7.0 reference disk that the recorded
/// System-resource hashes come from. The disk-level values are constants of
/// that disk; the resource fork hash can be overridden by callers that hashed
/// the user's actual System file resource fork.
enum System7Reference {
    static let diskName = "System 7.0 HD.dsk (infinite-mac)"
    static let sourceURL = "https://raw.githubusercontent.com/mihaip/infinite-mac/main/Images/System%207.0%20HD.dsk"
    static let sourceRevision = "095b0fa8b5161d51fc11856d107bcfbbb605f5cd"
    static let diskSHA256 = "691e76c73a88cd04ced93ec2c84661ca4d900581790e65188ce495f381b005b1"
    static let diskLength = 41_943_040
    static let hfsPath = "System Folder:System"
    static let resourceForkSHA256 = "edb31a497602d6141f82d85300d2f4a88c167327531f993b829bfb274cbb9668"
}

extension MacResourceFork {
    /// Looks a resource up, producing a user-facing error naming what is missing.
    func require(_ type: String, _ id: Int, from source: String) throws -> MacResource {
        guard let resource = self[type, id] else { throw MissingResource(type: type, id: id, source: source) }
        return resource
    }
}

struct MissingResource: Error, CustomStringConvertible {
    let type: String
    let id: Int
    let source: String
    var description: String { "\(source) does not contain the required resource '\(type)' \(id)" }
}
