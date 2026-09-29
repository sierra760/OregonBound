import Foundation

// Port of scripts/graphics_extract/pict.py (native indexed PackBits path
// only; the reference's `sips` subprocess fallback is deliberately absent)
// and scripts/extract_pict_text.py (text-only PICT v1 → run list).

enum PICTDecoder {
    static let headerLength = 10
    static let v2HeaderLength = 24
    static let packBitsRect: UInt16 = 0x0098

    /// pict.convert_pict without the `sips` fallback. The one Oregon Color
    /// PICT (10256) is an indexed PackBits rectangle and takes the native path;
    /// anything else yields a failed record instead of a shell-out.
    static func convert(resource: ResourceInfo, data: Data) -> DecodedImage {
        var diagnostics: [DecodeDiagnostic] = []
        var width: Int? = nil
        var height: Int? = nil
        do {
            let (normalized, normalizeDiagnostics) = try normalize(ByteSource(data))
            diagnostics = normalizeDiagnostics
            let frame = try normalized.rect(2)
            width = frame.width
            height = frame.height
            if frame.width <= 0 || frame.height <= 0 {
                diagnostics.append(DecodeDiagnostic(
                    "error", "pict.invalid_dimensions", "Invalid PICT dimensions: \(frame.width)x\(frame.height)"))
                return DecodedImage.failed(resource, diagnostics: diagnostics)
            }
            if let image = try convertIndexedPackBits(normalized) {
                return DecodedImage(
                    resource: resource,
                    status: diagnostics.contains { $0.severity == "warning" } ? .partial : .ok,
                    imagePath: nil,
                    width: image.width,
                    height: image.height,
                    mode: "RGBA",
                    frameIndex: 0,
                    frameCount: 1,
                    byteRanges: ["pict": [0, data.count]],
                    diagnostics: diagnostics,
                    image: image)
            }
            diagnostics.append(DecodeDiagnostic(
                "error", "pict.unsupported_encoding",
                "PICT is not an indexed PackBits rectangle; the reference pipeline's sips fallback is unavailable at runtime"))
            return DecodedImage.failed(resource, width: width, height: height, diagnostics: diagnostics)
        } catch {
            diagnostics.append(DecodeDiagnostic("error", "pict.decode_failed", "\(error)"))
            return DecodedImage.failed(resource, width: width, height: height, diagnostics: diagnostics)
        }
    }

    // MARK: - Frame normalization

    /// pict.normalize_pict: shift a frame with a negative origin to (0, 0),
    /// moving the clip rectangle along with it.
    static func normalize(_ data: ByteSource) throws -> (data: ByteSource, diagnostics: [DecodeDiagnostic]) {
        if data.count < headerLength {
            throw ReferenceDecodeError.value("PICT header requires \(headerLength) bytes; got \(data.count)")
        }
        let frame = try data.rect(2)
        if frame.top >= 0 && frame.left >= 0 { return (data, []) }

        var working = data.bytes
        let dt = max(0, -frame.top)
        let dl = max(0, -frame.left)
        writeRect(&working, at: 2, QuickDrawRect(top: frame.top + dt, left: frame.left + dl,
                                                  bottom: frame.bottom + dt, right: frame.right + dl))
        if let clipOffset = scanToClipRegion(working), clipOffset + 10 <= working.count {
            let shifted = ByteSource(working)
            let regionSize = Int(try shifted.u16(clipOffset))
            if regionSize >= 10 {
                let rectOffset = clipOffset + 2
                let clip = try shifted.rect(rectOffset)
                writeRect(&working, at: rectOffset, QuickDrawRect(top: clip.top + dt, left: clip.left + dl,
                                                                  bottom: clip.bottom + dt, right: clip.right + dl))
            }
        }
        return (ByteSource(working),
                [DecodeDiagnostic("info", "pict.normalized_frame", "Shifted negative PICT frame to origin")])
    }

    /// pict._scan_to_cliprgn: byte offset of the clip region size word, if a
    /// version-1 opcode stream reaches a clip opcode within 256 bytes.
    static func scanToClipRegion(_ data: [UInt8]) -> Int? {
        let opcodeSizes: [UInt8: Int] = [
            0x00: 0, 0x11: 1, 0x03: 2, 0x04: 1, 0x05: 2, 0x06: 4, 0x07: 4, 0x08: 2, 0x09: 8, 0x0A: 8,
            0x0B: 4, 0x0C: 4, 0x0D: 2, 0x0E: 4, 0x0F: 4, 0x10: 8, 0x12: 2, 0x13: 4, 0x15: 2, 0x16: 2, 0x17: 2,
        ]
        var offset = headerLength
        let limit = min(offset + 256, data.count - 1)
        while offset < limit {
            let opcode = data[offset]
            if opcode == 0x01 { return offset + 1 }
            guard let size = opcodeSizes[opcode] else { return nil }
            offset += 1 + size
        }
        return nil
    }

    private static func writeRect(_ bytes: inout [UInt8], at offset: Int, _ rect: QuickDrawRect) {
        for (index, value) in [rect.top, rect.left, rect.bottom, rect.right].enumerated() {
            let field = UInt16(truncatingIfNeeded: value)
            bytes[offset + index * 2] = UInt8(field >> 8)
            bytes[offset + index * 2 + 1] = UInt8(field & 0xff)
        }
    }

    // MARK: - Indexed PackBits rectangle

    /// pict._convert_indexed_packbits_pict: walk word opcodes to the first
    /// PackBitsRect and decode it; nil when the picture is anything else.
    static func convertIndexedPackBits(_ data: ByteSource) throws -> PNGEncoder.Image? {
        if data.count < headerLength { return nil }
        let frame = try data.rect(2)
        var offset = headerLength
        while offset + 2 <= data.count {
            let opcodeOffset = offset
            let opcode = try data.u16(offset)
            offset += 2
            switch opcode {
            case packBitsRect:
                return try decodePackBitsRect(data, opcodeOffset: opcodeOffset, frame: frame)
            case 0x0011:
                offset += 2
            case 0x0C00:
                offset += v2HeaderLength
            case 0x0001:
                if offset + 2 > data.count { return nil }
                let regionSize = Int(try data.u16(offset))
                if regionSize < 2 { return nil }
                offset += regionSize
            default:
                return nil
            }
        }
        return nil
    }

    /// pict._decode_packbits_rect: an 8-bit indexed PackBitsRect whose bounds,
    /// source and destination rectangles all equal the picture frame.
    static func decodePackBitsRect(_ data: ByteSource, opcodeOffset: Int, frame: QuickDrawRect) throws -> PNGEncoder.Image? {
        var cursor = opcodeOffset + 2
        if cursor + 46 > data.count { return nil }

        let rowBytes = Int(try data.u16(cursor) & 0x3FFF)
        let bounds = try data.rect(cursor + 2)
        let pixelSize = Int(try data.u16(cursor + 28))
        let componentCount = Int(try data.u16(cursor + 30))
        let componentSize = Int(try data.u16(cursor + 32))
        cursor += 46

        let width = bounds.width
        let height = bounds.height
        if rowBytes <= 0 || width <= 0 || height <= 0 { return nil }
        if pixelSize != 8 || componentCount != 1 || componentSize != 8 { return nil }
        if cursor + 8 > data.count { return nil }

        let colorTableSize = Int(try data.u16(cursor + 6))
        cursor += 8
        if colorTableSize > 255 || cursor + (colorTableSize + 1) * 8 > data.count { return nil }

        var palette = [UInt8](repeating: 255, count: 256 * 3)
        for _ in 0...colorTableSize {
            let value = Int(try data.u16(cursor))
            let red = UInt8(try data.u16(cursor + 2) >> 8)
            let green = UInt8(try data.u16(cursor + 4) >> 8)
            let blue = UInt8(try data.u16(cursor + 6) >> 8)
            cursor += 8
            if value < 256 {
                palette[value * 3] = red
                palette[value * 3 + 1] = green
                palette[value * 3 + 2] = blue
            }
        }

        if cursor + 18 > data.count { return nil }
        let sourceRect = try data.rect(cursor)
        cursor += 8
        let destinationRect = try data.rect(cursor)
        cursor += 8
        let mode = try data.u16(cursor)
        cursor += 2

        let sourceWidth = sourceRect.width
        let sourceHeight = sourceRect.height
        if sourceWidth <= 0 || sourceHeight <= 0 { return nil }
        if bounds != frame { return nil }
        if mode != 0 { return nil }
        if sourceRect != bounds { return nil }
        if destinationRect != bounds { return nil }

        // PIL putdata fills sequentially: rows are concatenated, then padded
        // or truncated to the image size.
        var indices: [UInt8] = []
        indices.reserveCapacity(sourceWidth * sourceHeight)
        for _ in 0..<sourceHeight {
            let byteCount: Int
            if rowBytes > 250 {
                if cursor + 2 > data.count { return nil }
                byteCount = Int(try data.u16(cursor))
                cursor += 2
            } else {
                if cursor >= data.count { return nil }
                byteCount = Int(data.bytes[cursor])
                cursor += 1
            }
            let (row, next) = try unpackPackBitsRow(data, offset: cursor, byteCount: byteCount, rowBytes: rowBytes)
            cursor = next
            indices.append(contentsOf: row[max(0, min(sourceRect.left, row.count))..<max(0, min(sourceRect.left + sourceWidth, row.count))])
        }
        let pixelCount = sourceWidth * sourceHeight
        if indices.count < pixelCount { indices += [UInt8](repeating: 0, count: pixelCount - indices.count) }

        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
        for pixel in 0..<pixelCount {
            let index = Int(indices[pixel]) * 3
            rgba[pixel * 4] = palette[index]
            rgba[pixel * 4 + 1] = palette[index + 1]
            rgba[pixel * 4 + 2] = palette[index + 2]
        }
        return PNGEncoder.Image(width: sourceWidth, height: sourceHeight, colorType: .rgba, pixels: rgba)
    }

    /// pict._unpack_packbits_row: one PackBits row, padded or trimmed to
    /// `rowBytes`; the cursor always advances by the declared `byteCount`.
    static func unpackPackBitsRow(_ data: ByteSource, offset: Int, byteCount: Int, rowBytes: Int) throws -> (row: [UInt8], next: Int) {
        let end = offset + byteCount
        var row: [UInt8] = []
        row.reserveCapacity(rowBytes)
        var cursor = offset
        while cursor < end && row.count < rowBytes {
            let control = Int(try data.byte(cursor))
            cursor += 1
            if control <= 127 {
                let count = control + 1
                row.append(contentsOf: data.slice(cursor, cursor + count))
                cursor += count
            } else if control >= 129 {
                let count = 257 - control
                if cursor < end {
                    let value = try data.byte(cursor)
                    row.append(contentsOf: [UInt8](repeating: value, count: count))
                }
                cursor += 1
            }
        }
        if row.count < rowBytes { row += [UInt8](repeating: 0, count: rowBytes - row.count) }
        return (Array(row.prefix(rowBytes)), end)
    }
}

/// A text-only PICT v1 decoded to its original QuickDraw text runs
/// (scripts/extract_pict_text.py). Baselines and origins are relative to the
/// picture frame; no font substitution happens here.
struct TextPicture: Encodable, Equatable {
    struct Run: Encodable, Equatable {
        var x: Int
        var baseline: Int
        var font: Int
        var face: Int
        var size: Int
        var text: String
    }
    var id: Int
    var width: Int
    var height: Int
    var runs: [Run]
}

enum TextPictureDecoder {
    /// extract_pict_text.decode. Fails on any opcode other than the text and
    /// text-state opcodes the original pictures use.
    static func decode(_ data: Data, resourceId: Int) throws -> TextPicture {
        let source = ByteSource(data)
        try source.requireUnpack(0, 10)  // ">Hhhhh"
        let size = Int(try source.u16(0))
        let frame = try source.rect(2)
        if size != source.count || Array(source.slice(10, 12)) != [0x11, 0x01] {
            throw ReferenceDecodeError.value("Expected a complete PICT v1 resource")
        }
        var at = 12
        var font = 0, face = 0, pointSize = 12
        var x = 0, y = 0
        var runs: [TextPicture.Run] = []
        var ended = false
        while at < source.count {
            let opcode = source.bytes[at]
            at += 1
            if opcode == 0xff { ended = true; break }
            switch opcode {
            case 0:
                continue
            case 1:
                let regionSize = Int(try source.u16(at))
                if regionSize != 10 { throw ReferenceDecodeError.value("Nonrectangular clip is unsupported") }
                at += regionSize
            case 3:
                font = Int(try source.u16(at)); at += 2
            case 4:
                face = Int(try source.byte(at)); at += 1
            case 0x0d:
                pointSize = Int(try source.u16(at)); at += 2
            case 0x28, 0x29, 0x2a, 0x2b:
                if opcode == 0x28 {
                    y = Int(try source.i16(at))
                    x = Int(try source.i16(at + 2))
                    at += 4
                } else {
                    if opcode == 0x29 || opcode == 0x2b { x += Int(try source.byte(at)); at += 1 }
                    if opcode == 0x2a || opcode == 0x2b { y += Int(try source.byte(at)); at += 1 }
                }
                let length = Int(try source.byte(at)); at += 1
                let text = MacRoman.decode(source.slice(at, at + length)); at += length
                runs.append(TextPicture.Run(x: x - frame.left, baseline: y - frame.top,
                                            font: font, face: face, size: pointSize, text: text))
            default:
                throw ReferenceDecodeError.value(
                    "Unsupported PICT opcode \(hex(Int(opcode))) at \(hex(at - 1))")
            }
        }
        if !ended || at != source.count { throw ReferenceDecodeError.value("PICT boundary mismatch") }
        return TextPicture(id: resourceId, width: frame.width, height: frame.height, runs: runs)
    }

    /// Python `f"{value:#x}"`.
    private static func hex(_ value: Int) -> String { "0x" + String(value, radix: 16) }
}
