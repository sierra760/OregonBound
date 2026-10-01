import Foundation

/// CD CODE10 converts Ima4's 8-bit indices through A5-2312 and clut1004.
/// The map is derived from the supplied CODE23 initializer, never bundled.
struct CD16Palette {
    let indices: [UInt8]
    let palette: [UInt8]

    init(initializer: Data, colorTable: Data) throws {
        // Resource header: jump-table offset and the initializer's one entry.
        guard initializer.count >= 4, try ByteSource(initializer).u16(2) == 1 else {
            throw ReferenceDecodeError.value("Unsupported CD initializer segment")
        }
        let memory = try Self.initializedBytes(Data(initializer.dropFirst(4)))
        guard memory.count >= 0x2312 else {
            throw ReferenceDecodeError.value("CD initializer does not contain the color-index table")
        }
        let colors = ByteSource(colorTable)
        guard colors.count == 136, try colors.u16(4) == 0x8000, try colors.u16(6) == 15 else {
            throw ReferenceDecodeError.value("Invalid CD 16-color palette")
        }
        let start = memory.count - 0x2312
        indices = Array(memory[start..<start + 256])
        guard indices.allSatisfy({ $0 <= 15 }) else {
            throw ReferenceDecodeError.value("Invalid CD 16-color conversion")
        }
        palette = try QuickDrawColorTable.parse(colors, at: 0).flatMap { [$0.red, $0.green, $0.blue] } + Array(repeating: 0, count: 720)
    }

    /// Expand only version-1 initialized bytes; pointer relocations do not apply
    /// to this byte table. Input, output, recursion and repetition are bounded.
    static func initializedBytes(_ code: Data) throws -> [UInt8] {
        let source = ByteSource(code)
        guard (8...1024*1024).contains(source.count),
              source.bytes.prefix(6).elementsEqual([0x48,0xe7,0x7f,0xf8,0x49,0xfa]) else {
            throw ReferenceDecodeError.value("Unsupported CD initializer")
        }
        let header = 6 + Int(try source.i16(6))
        guard header >= 8, header + 16 <= source.count else {
            throw ReferenceDecodeError.value("Invalid CD initializer header")
        }
        let size = Int(try source.u32(header)), start = Int(try source.u32(header + 8))
        let end = Int(try source.u32(header + 12))
        guard (1...1024*1024).contains(size), try source.u16(header + 4) == 1,
              try source.u16(header + 6) == 0, start >= 16, start < end, end <= source.count - header else {
            throw ReferenceDecodeError.value("Invalid CD initializer bounds or version")
        }
        var cursor = header + start, destination = 0, repeats = 1
        let limit = header + end
        var memory = [UInt8](repeating: 0, count: size)
        func byte() throws -> Int {
            guard cursor < limit else { throw ReferenceDecodeError.value("Truncated CD initializer stream") }
            defer { cursor += 1 }
            return Int(source.bytes[cursor])
        }
        func number(_ depth: Int = 0) throws -> Int {
            guard depth < 8 else { throw ReferenceDecodeError.value("Nested CD initializer repetition") }
            let first = try byte()
            if first < 0x80 { return first }
            if first < 0xc0 { return try ((first & 0x3f) << 8) | byte() }
            if first < 0xe0 { return try ((first & 0x1f) << 16) | (byte() << 8) | byte() }
            if first < 0xf0 { return try (byte() << 24) | (byte() << 16) | (byte() << 8) | byte() }
            repeats = try number(depth + 1)
            let second = try number(depth + 1)
            // The second recursive call may change d3 before d0/d3 EXG.
            let value = repeats
            repeats = second
            return value
        }
        while true {
            repeats = 1
            let operation = try byte()
            var count = (operation & 15) * 2
            if count == 0 {
                count = try number()
                if count == 0 {
                    guard cursor == limit else { throw ReferenceDecodeError.value("Trailing CD initializer data") }
                    return memory
                }
            }
            var skip = (operation & 0xf0) >> 3
            if skip == 0 { skip = try number() }
            guard count <= size, skip <= size, repeats >= 1,
                  repeats <= (size - destination) / (skip + count), repeats <= (limit - cursor) / count else {
                throw ReferenceDecodeError.value("CD initializer operation exceeds bounds")
            }
            for _ in 0..<repeats {
                destination += skip
                memory.replaceSubrange(destination..<destination + count, with: source.bytes[cursor..<cursor + count])
                destination += count; cursor += count
            }
        }
    }

    func convert(_ record: DecodedImage) throws -> DecodedImage {
        guard record.resource.resourceType == "Ima4", let image = record.image,
              image.colorType == .indexed, image.transparency == nil else {
            throw ReferenceDecodeError.value("CD 16-color conversion requires an indexed Ima4 frame")
        }
        var result = record
        result.image = PNGEncoder.Image(width: image.width, height: image.height, colorType: .indexed,
                                        pixels: image.pixels.map { indices[Int($0)] }, palette: palette)
        result.palette = PaletteInfo(source: "cd_16_color", entryCount: 16, resourceId: 1004)
        result.diagnostics.removeAll { $0.code == "imag.palette_fallback" }
        if result.status == .partial && !result.diagnostics.contains(where: { ["warning", "error"].contains($0.severity) }) {
            result.status = .ok
        }
        return result
    }
}
