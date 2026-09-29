import Foundation

// Port of scripts/graphics_extract/imag.py (frame container) and
// scripts/graphics_extract/imag_codec.py (MECC row codec, CODE 20).
// Row operations follow the original machine code; every quirk of the
// reference implementation is reproduced so the output is pixel-identical.

enum ImagDecoder {
    static let headerSize = 6            // MECC 6-byte resource header (count + first frame length)
    static let pixMapSize = 50           // QuickDraw PixMap struct
    static let dataOffset = headerSize + pixMapSize  // 56: first frame's payload

    /// Largest backing store a single frame may declare (guards hostile input;
    /// the original game's largest frame is 494x304).
    static let maximumFrameBytes = 64 * 1024 * 1024

    // MARK: - Container (imag.py)

    /// imag.decode_imag: length-prefixed frames as walked by the original
    /// Display loader (CODE 5:0x5b8c / 0x5ba2). Each frame carries a fresh
    /// 50-byte PixMap; pmTable == 0 means an inline color table follows.
    static func decode(resource: ResourceInfo, data: Data, fallbackPalette: [UInt8],
                       fallbackSource: String) -> [DecodedImage] {
        let source = ByteSource(data)
        var records: [DecodedImage] = []
        var pending: [DecodeDiagnostic] = []
        var frameCount = 0
        do {
            frameCount = Int(try source.u16(0))
            if frameCount == 0 { throw ReferenceDecodeError.value("Imag declares no frames") }
            var frameStart = 2
            var palette = fallbackPalette
            var paletteInfo = PaletteInfo(source: fallbackSource, entryCount: 256)
            var inheritedPalette = false
            for frameIndex in 0..<frameCount {
                if frameStart + 54 > source.count {
                    pending.append(DecodeDiagnostic(
                        "error", "imag.truncated_frame_header",
                        "Frame \(frameIndex) has no complete length and PixMap at \(frameStart)"))
                    break
                }
                let frameLength = Int(try source.u32(frameStart))
                if frameLength < 54 || frameStart + frameLength > source.count {
                    pending.append(DecodeDiagnostic(
                        "error", "imag.invalid_frame_length",
                        "Frame \(frameIndex) length \(frameLength) at \(frameStart) exceeds its resource or header"))
                    break
                }
                let frameEnd = frameStart + frameLength
                let pixmap = try QuickDrawPixMap(parsing: source, at: frameStart + 4)
                let width = pixmap.width, height = pixmap.height, rowBytes = pixmap.rowBytes
                if !pixmap.isPixMap || pixmap.pixelSize != 8 || width <= 0 || height <= 0 || rowBytes < width {
                    throw ReferenceDecodeError.value("Invalid 8-bit PixMap in frame \(frameIndex): \(pixmap.pythonDescription)")
                }
                var pixelStart = frameStart + 54
                var frameDiagnostics: [DecodeDiagnostic] = []
                // CODE 5:0x5d8c–0x5d94: pmTable==0 means an inline color table.
                // Nonzero pointers inherit the last inline palette (0x5b8e–0x5bb2).
                let tablePointer = try source.u32(frameStart + 46)
                if tablePointer == 0 {
                    if pixelStart + 8 > frameEnd {
                        throw ReferenceDecodeError.value("Truncated color table in frame \(frameIndex)")
                    }
                    let count = Int(try source.u16(pixelStart + 6)) + 1
                    let tableSize = 8 + count * 8
                    if count > 256 || pixelStart + tableSize > frameEnd {
                        throw ReferenceDecodeError.value("Invalid color table size in frame \(frameIndex)")
                    }
                    palette = try QuickDrawColorTable.paletteBytes(fromColorTable: source, at: pixelStart)
                    paletteInfo = PaletteInfo(source: "inline_ctable", entryCount: count)
                    inheritedPalette = true
                    pixelStart += tableSize
                } else if !inheritedPalette {
                    frameDiagnostics.append(DecodeDiagnostic(
                        "warning", "imag.palette_fallback", "Using \(fallbackSource) palette"))
                }
                if pixelStart + 5 > frameEnd {
                    pending.append(DecodeDiagnostic(
                        "error", "imag.truncated_frame_header", "Frame \(frameIndex) has no compression header"))
                    break
                }
                let compWidth = Int(try source.u16LE(pixelStart))
                let compHeight = Int(try source.u16LE(pixelStart + 2))
                if compWidth * compHeight != rowBytes * height {
                    frameDiagnostics.append(DecodeDiagnostic(
                        "error", "imag.backing_size_mismatch",
                        "Compression layout \(compWidth)x\(compHeight) does not match PixMap backing store \(rowBytes)x\(height)"))
                }
                let (framePixels, endOffset) = try decodeFrame(
                    source.prefix(frameEnd), start: pixelStart, displayWidth: width, displayHeight: height, alignEnd: false)
                if endOffset > frameEnd {
                    frameDiagnostics.append(DecodeDiagnostic(
                        "warning", "imag.frame_boundary_overread",
                        "Frame ended at \(endOffset), past declared boundary \(frameEnd)"))
                }
                let image = PNGEncoder.Image(
                    width: width, height: height, colorType: .indexed,
                    pixels: cropBackingStore(framePixels, width: width, height: height, rowBytes: rowBytes),
                    palette: palette)
                records.append(DecodedImage(
                    resource: resource, status: status(for: frameDiagnostics), imagePath: nil,
                    width: width, height: height, mode: "P",
                    frameIndex: frameIndex, frameCount: frameCount, palette: paletteInfo,
                    byteRanges: ["pixels": [pixelStart, min(endOffset, frameEnd)]],
                    diagnostics: frameDiagnostics, image: image))
                frameStart = frameEnd
            }
        } catch {
            pending.append(DecodeDiagnostic("error", "imag.decode_failed", "\(error)"))
        }
        if records.count < frameCount {
            pending.append(DecodeDiagnostic(
                "warning", "imag.decoded_frame_shortfall",
                "Decoded \(records.count) frames for declared count \(frameCount)"))
        }
        if records.isEmpty {
            return [DecodedImage.failed(
                resource, diagnostics: pending + [DecodeDiagnostic("error", "imag.no_frames", "No frames decoded")])]
        }
        for index in records.indices {
            records[index].diagnostics += pending
            records[index].status = status(for: records[index].diagnostics)
        }
        return records
    }

    /// imag.fallback_palette_from_resources: the palette used by frames whose
    /// PixMap points at a shared color table instead of carrying one inline.
    static func fallbackPalette(from fork: MacResourceFork) throws -> (palette: [UInt8], source: String) {
        if let imag19000 = fork["Imag", 19000] {
            let source = ByteSource(imag19000.data)
            if QuickDrawColorTable.detectInlineColorTable(source, at: dataOffset).present {
                return (try QuickDrawColorTable.paletteBytes(fromColorTable: source, at: dataOffset), "imag_19000_inline_ctable")
            }
        }
        if let clut1008 = fork["clut", 1008] {
            return (try QuickDrawColorTable.paletteBytes(fromColorTable: ByteSource(clut1008.data), at: 0), "clut_1008")
        }
        return ([UInt8](repeating: 0, count: 256 * 3), "zero_palette")
    }

    /// imag._status_for_diagnostics.
    static func status(for diagnostics: [DecodeDiagnostic]) -> DecodeStatus {
        diagnostics.contains { $0.severity == "warning" || $0.severity == "error" } ? .partial : .ok
    }

    /// imag._crop_backing_store_to_bounds: the decoded buffer is laid out with
    /// `rowBytes` stride; keep `width` bytes of each of `height` rows.
    static func cropBackingStore(_ pixels: [UInt8], width: Int, height: Int, rowBytes: Int) -> [UInt8] {
        var cropped = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let sourceRow = row * rowBytes
            for column in 0..<width {
                let index = sourceRow + column
                if index < pixels.count { cropped[row * width + column] = pixels[index] }
            }
        }
        return cropped
    }

    // MARK: - Row codec (imag_codec.py)

    /// imag_codec.mecc_rle (A5+0x132): "inverted PackBits". ctrl < 0x80 is a
    /// run of (ctrl+1) copies of the next `patternLength` bytes; ctrl >= 0x80
    /// copies (ctrl-0x7f) literal bytes. Returns the decoded bytes and the
    /// number of source bytes consumed from `start`.
    static func meccRLE(_ data: ByteSource, start: Int, target: Int, patternLength: Int = 1) -> (decoded: [UInt8], consumed: Int) {
        var result: [UInt8] = []
        result.reserveCapacity(max(0, target))
        var i = start
        let end = data.count
        let patternLength = max(1, patternLength)
        while result.count < target && i < end {
            let control = Int(data.bytes[i])
            if control < 0x80 {
                let pattern = data.slice(i + 1, i + 1 + patternLength)
                for _ in 0..<(control + 1) { result.append(contentsOf: pattern) }
                i += 1 + patternLength
            } else {
                let n = control - 0x7f
                result.append(contentsOf: data.slice(i + 1, i + 1 + n))
                i += 1 + n
            }
        }
        return (result, i - start)
    }

    /// imag_codec.fun_00000aba: pattern repeat with an explicit pattern length
    /// byte (ctrl < 0x80) or literal copy (ctrl >= 0x80).
    static func fun00000aba(_ data: ByteSource, start: Int, target: Int) -> (decoded: [UInt8], consumed: Int) {
        var result: [UInt8] = []
        result.reserveCapacity(max(0, target))
        var i = start
        let end = data.count
        while result.count < target && i < end {
            let control = Int(data.bytes[i])
            if control < 0x80 {
                i += 1
                if i >= end { break }
                let patternLength = Int(data.bytes[i])
                let pattern = data.slice(i + 1, i + 1 + patternLength)
                for _ in 0..<(control + 1) { result.append(contentsOf: pattern) }
                i += 1 + patternLength
            } else {
                let n = control - 0x7f
                result.append(contentsOf: data.slice(i + 1, i + 1 + n))
                i += control - 0x7e
            }
        }
        return (result, i - start)
    }

    private static let bitMasks = [0x00, 0x01, 0x03, 0x07, 0x0F, 0x1F, 0x3F, 0x7F]
    private static let bitStrides = [0, 1, 1, 3, 1, 5, 3, 7]
    private static let bitGroups = [0, 8, 4, 8, 2, 8, 4, 8]
    private static let bitByteOffsets: [Int: [Int]] = [
        1: [0, 0, 0, 0, 0, 0, 0, 0],
        2: [0, 0, 0, 0],
        3: [0, 0, 0, 1, 1, 1, 2, 2],
        4: [0, 0],
        5: [0, 0, 1, 1, 2, 3, 3, 4],
        6: [0, 0, 1, 2],
        7: [0, 0, 1, 2, 3, 4, 5, 6],
    ]
    private static let bitShifts: [Int: [Int]] = [
        1: [0, 1, 2, 3, 4, 5, 6, 7],
        2: [0, 2, 4, 6],
        3: [0, 3, 6, 1, 4, 7, 2, 5],
        4: [0, 4],
        5: [0, 5, 2, 7, 4, 1, 6, 3],
        6: [0, 6, 4, 2],
        7: [0, 7, 6, 5, 4, 3, 2, 1],
    ]

    /// imag_codec.expand_bits (A5+0x12a): unpack `depth`-bit fields from
    /// little-endian 16-bit windows into exactly `targetPixels` bytes.
    static func expandBits(_ data: ArraySlice<UInt8>, depth: Int, targetPixels: Int) -> [UInt8] {
        let targetPixels = max(0, targetPixels)
        if depth == 8 {
            var result = Array(data.prefix(targetPixels))
            if result.count < targetPixels {
                result += [UInt8](repeating: 0, count: targetPixels - result.count)
            }
            return result
        }
        guard depth >= 1, depth <= 8, let offsets = bitByteOffsets[depth], let shifts = bitShifts[depth] else {
            return [UInt8](repeating: 0, count: targetPixels)
        }
        var result: [UInt8] = []
        result.reserveCapacity(targetPixels)
        let mask = bitMasks[depth]
        let stride = bitStrides[depth]
        let group = bitGroups[depth]
        let base0 = data.startIndex
        let count = data.count
        var base = 0
        var index = 0
        while result.count < targetPixels {
            let byteIndex = base + offsets[index]
            let lo = byteIndex < count ? Int(data[base0 + byteIndex]) : 0
            let hiIndex = byteIndex + 1
            let hi = hiIndex < count ? Int(data[base0 + hiIndex]) : 0
            let value = ((hi << 8) | lo) >> shifts[index]
            result.append(UInt8(value & mask))
            index += 1
            if index == group {
                index = 0
                base += stride
            }
        }
        return result
    }

    /// imag_codec.expand_bits_signed (FUN_00000896): the same fields,
    /// sign-extended.
    static func expandBitsSigned(_ data: ArraySlice<UInt8>, depth: Int, targetPixels: Int) -> [Int] {
        let raw = expandBits(data, depth: depth, targetPixels: targetPixels)
        if depth >= 8 {
            return raw.map { $0 < 128 ? Int($0) : Int($0) - 256 }
        }
        let signBit = 1 << (depth - 1)
        var result: [Int] = []
        result.reserveCapacity(max(0, targetPixels))
        for byte in raw {
            let value = Int(byte)
            result.append(value & signBit != 0 ? value - (1 << depth) : value)
            if result.count >= targetPixels { break }
        }
        while result.count < targetPixels { result.append(0) }
        return result
    }

    /// imag_codec.fun_000009cc: running modular delta over signed symbols,
    /// mapped through the `ivar5` indirection table.
    static func fun000009cc(rowBuffer: [Int], compWidth: Int, ivar5: [UInt8], ivar5Count: Int, depth: Int) -> (pixels: [UInt8], consumed: Int) {
        if ivar5Count <= 0 { return ([UInt8](repeating: 0, count: compWidth), 0) }
        var output = [UInt8](repeating: 0, count: compWidth)
        let cvar2 = 1 << (depth - 1)
        let mask = cvar2 - 1
        let maskSigned = mask < 128 ? mask : mask - 256
        let negative2 = -cvar2
        var uvar5 = 0    // running palette index (unsigned 8-bit)
        var uvar3 = 0    // index into rowBuffer
        for local6 in 0..<compWidth {
            if uvar3 >= rowBuffer.count { break }
            var cvar6 = rowBuffer[uvar3]
            while true {
                uvar3 += 1
                if maskSigned != cvar6 && negative2 != cvar6 { break }
                let uvar5Signed = uvar5 < 128 ? uvar5 : uvar5 - 256
                uvar5 = (uvar5Signed + cvar6) & 0xFF
                if uvar3 >= rowBuffer.count { break }
                cvar6 = rowBuffer[uvar3]
            }
            let uvar5Signed = uvar5 < 128 ? uvar5 : uvar5 - 256
            cvar6 += uvar5Signed
            if cvar6 < 0 { cvar6 += ivar5Count }
            if cvar6 > ivar5Count - 1 { cvar6 -= ivar5Count }
            uvar5 = cvar6 & 0xFF
            if cvar6 >= 0 && cvar6 < ivar5.count { output[local6] = ivar5[cvar6] }
        }
        return (output, uvar3)
    }

    /// imag_codec.fun_000018e4 (A5+0x13a): unsigned symbols where the all-ones
    /// value for the depth accumulates into the next index.
    static func fun000018e4(rowBuffer: [UInt8], compWidth: Int, ivar5: [UInt8], depth: Int) -> (pixels: [UInt8], consumed: Int) {
        if ivar5.isEmpty { return ([UInt8](repeating: 0, count: compWidth), 0) }
        let special = depth >= 0 && depth < bitMasks.count ? bitMasks[depth] : 0xFF
        var output = [UInt8](repeating: 0, count: compWidth)
        var consumed = 0
        for pixel in 0..<compWidth {
            var accumulator = 0
            var value = 0
            while true {
                if consumed >= rowBuffer.count { return (output, consumed) }
                value = Int(rowBuffer[consumed])
                consumed += 1
                if value != special { break }
                accumulator = (accumulator + value) & 0xFF
            }
            let index = (accumulator + value) & 0xFF
            if index < ivar5.count { output[pixel] = ivar5[index] }
        }
        return (output, consumed)
    }

    /// imag_codec.decode_frame (FUN_00000002): one frame from the row-opcode
    /// stream starting at `start` (the 5-byte little-endian compression header).
    /// Returns the raw backing-store buffer in the header's layout and the
    /// offset just past the consumed bytes (word-aligned when `alignEnd`).
    static func decodeFrame(_ data: ByteSource, start: Int, displayWidth: Int, displayHeight: Int,
                            alignEnd: Bool = true) throws -> (pixels: [UInt8], endOffset: Int) {
        let count = data.count
        let displayBytes = max(0, displayWidth * displayHeight)
        if start + 5 > count { return ([UInt8](repeating: 0, count: displayBytes), start) }
        let compWidth = Int(try data.u16LE(start))
        let compHeight = Int(try data.u16LE(start + 2))
        if compWidth == 0 || compHeight == 0 {
            return ([UInt8](repeating: 0, count: displayBytes), start + 5)
        }
        guard compWidth * compHeight <= maximumFrameBytes else {
            throw ReferenceDecodeError.value(
                "Imag frame backing store \(compWidth)x\(compHeight) exceeds \(maximumFrameBytes) bytes")
        }
        var ptr = start + 5
        var output = [UInt8](repeating: 0, count: compWidth * compHeight)
        // ivar5: palette indirection table filled by case 3 / sub 6 opcodes.
        var ivar5 = [UInt8](repeating: 0, count: 256)
        var ivar5Count = 0
        // Row index → (offset of the count byte, entry count) for back-references.
        var rowPaletteCache: [Int: (pointer: Int, count: Int)] = [:]
        var row = 0
        let bytes = data.bytes

        func storeRow(_ rowOffset: Int, _ values: ArraySlice<UInt8>) {
            // Python assigns a possibly-shorter slice; here the remainder stays zero.
            let length = min(compWidth, values.count)
            if length > 0 {
                output.replaceSubrange(rowOffset..<rowOffset + length, with: values.prefix(length))
            }
        }

        rows: while row < compHeight {
            if ptr >= count { break }
            let opcode = Int(bytes[ptr])
            ptr += 1
            let opcodeCase = opcode >> 6
            let sub = (opcode & 0x38) >> 3
            let low = opcode & 7
            let rowOffset = row * compWidth

            switch opcodeCase {
            case 3:
                switch sub {
                case 0:
                    // Literal row.
                    storeRow(rowOffset, data.slice(ptr, ptr + compWidth))
                    ptr += compWidth
                    row += 1
                case 1:
                    // Solid fill.
                    let fill = try data.byte(ptr)
                    ptr += 1
                    for index in rowOffset..<rowOffset + compWidth { output[index] = fill }
                    row += 1
                case 2:
                    // Absolute row reference, one byte (CODE 20:0x568–0x578).
                    let referenceRow = Int(try data.byte(ptr))
                    ptr += 1
                    copyRow(&output, from: referenceRow, to: row, width: compWidth)
                    row += 1
                case 3:
                    // Absolute row reference, little-endian word (CODE 20:0x5b0–0x5ce).
                    let referenceRow = Int(try data.u16LE(ptr))
                    ptr += 2
                    copyRow(&output, from: referenceRow, to: row, width: compWidth)
                    row += 1
                case 4:
                    // Repeat the preceding row (CODE 20:0x604–0x618).
                    if row > 0 {
                        output.replaceSubrange(rowOffset..<rowOffset + compWidth,
                                               with: output[rowOffset - compWidth..<rowOffset])
                    }
                    row += 1
                case 5:
                    // Compressed row of 8-bit indices: low=7 → fun_00000aba, else MECC RLE.
                    let decoded: [UInt8]
                    let consumed: Int
                    if low == 7 {
                        (decoded, consumed) = fun00000aba(data, start: ptr, target: compWidth)
                    } else {
                        (decoded, consumed) = meccRLE(data, start: ptr, target: compWidth, patternLength: low)
                    }
                    storeRow(rowOffset, decoded[...])
                    ptr += consumed
                    row += 1
                case 6:
                    // ivar5 palette setup; does not advance the row.
                    if low == 0 {
                        let n = Int(try data.byte(ptr))
                        let paletteBytes = data.slice(ptr + 1, ptr + 1 + n)
                        ivar5.replaceSubrange(0..<paletteBytes.count, with: paletteBytes)
                        ivar5Count = n
                        rowPaletteCache[row] = (ptr, n)
                        ptr += n + 1
                    } else if low == 1 {
                        let back = Int(try data.byte(ptr))
                        ptr += 1
                        if let cached = rowPaletteCache[row - back] {
                            let paletteBytes = data.slice(cached.pointer + 1, cached.pointer + 1 + cached.count)
                            ivar5.replaceSubrange(0..<paletteBytes.count, with: paletteBytes)
                            ivar5Count = cached.count
                        }
                    } else if low == 2 {
                        let n = Int(try data.byte(ptr))
                        let back = Int(try data.byte(ptr + 1))
                        ptr += 2
                        if let cached = rowPaletteCache[row - back] {
                            let paletteBytes = data.slice(cached.pointer + 1, cached.pointer + 1 + n)
                            ivar5.replaceSubrange(0..<paletteBytes.count, with: paletteBytes)
                            ivar5Count = n
                        }
                    }
                default:
                    // Unknown sub-opcode: abandon the frame.
                    throw ReferenceDecodeError.value(
                        "Incomplete Imag frame: decoded \(row) of \(compHeight) compression rows")
                }

            case 2:
                // sub = bit depth, low = compression variant; direct ivar5 lookup.
                let depth = sub != 0 ? sub : 8
                let pixelCount = compWidth
                let targetBytes = (pixelCount * depth + 7) / 8
                let rowBuffer: [UInt8]
                if low == 7 {
                    let (decoded, consumed) = fun00000aba(data, start: ptr, target: targetBytes)
                    ptr += consumed
                    rowBuffer = expandBits(decoded[...], depth: depth, targetPixels: pixelCount)
                } else if low == 0 {
                    rowBuffer = expandBits(data.slice(ptr, count), depth: depth, targetPixels: pixelCount)
                    ptr += targetBytes
                } else {
                    let (decoded, consumed) = meccRLE(data, start: ptr, target: targetBytes, patternLength: low)
                    ptr += consumed
                    rowBuffer = expandBits(decoded[...], depth: depth, targetPixels: pixelCount)
                }
                for i in 0..<min(compWidth, rowBuffer.count) {
                    let index = Int(rowBuffer[i])
                    output[rowOffset + i] = index < ivar5.count ? ivar5[index] : 0
                }
                row += 1

            case 0:
                // [opcode][pixel_count LE16][compressed…]: signed expand + FUN_000009cc.
                if ptr + 1 >= count { break rows }
                let pixelCount = Int(bytes[ptr + 1]) * 0x100 + Int(bytes[ptr])
                let depth = sub != 0 ? sub : 8
                let targetBytes = (pixelCount * depth + 7) / 8
                let rowBufferSigned: [Int]
                if low == 7 {
                    let (decoded, consumed) = fun00000aba(data, start: ptr + 2, target: targetBytes)
                    ptr += 2 + consumed
                    rowBufferSigned = expandBitsSigned(decoded[...], depth: depth, targetPixels: pixelCount + 1)
                } else if low == 0 {
                    rowBufferSigned = expandBitsSigned(data.slice(ptr + 2, count), depth: depth, targetPixels: pixelCount + 1)
                    ptr += 2 + targetBytes
                } else {
                    let (decoded, consumed) = meccRLE(data, start: ptr + 2, target: targetBytes, patternLength: low)
                    ptr += 2 + consumed
                    rowBufferSigned = expandBitsSigned(decoded[...], depth: depth, targetPixels: pixelCount + 1)
                }
                let (rowPixels, _) = fun000009cc(rowBuffer: rowBufferSigned, compWidth: compWidth,
                                                 ivar5: ivar5, ivar5Count: ivar5Count, depth: depth)
                output.replaceSubrange(rowOffset..<rowOffset + compWidth, with: rowPixels)
                row += 1

            case 1:
                // [opcode][pixel_count LE16][compressed…]: unsigned expand + A5+0x13a.
                if ptr + 1 >= count { break rows }
                let pixelCount = Int(bytes[ptr + 1]) * 0x100 + Int(bytes[ptr])
                let depth = sub != 0 ? sub : 8
                let targetBytes = (pixelCount * depth + 7) / 8
                let rowBuffer: [UInt8]
                if low == 7 {
                    let (decoded, consumed) = fun00000aba(data, start: ptr + 2, target: targetBytes)
                    ptr += 2 + consumed
                    rowBuffer = expandBits(decoded[...], depth: depth, targetPixels: pixelCount + 1)
                } else if low == 0 {
                    rowBuffer = expandBits(data.slice(ptr + 2, count), depth: depth, targetPixels: pixelCount + 1)
                    ptr += 2 + targetBytes
                } else {
                    let (decoded, consumed) = meccRLE(data, start: ptr + 2, target: targetBytes, patternLength: low)
                    ptr += 2 + consumed
                    rowBuffer = expandBits(decoded[...], depth: depth, targetPixels: pixelCount + 1)
                }
                let (rowPixels, _) = fun000018e4(rowBuffer: rowBuffer, compWidth: compWidth, ivar5: ivar5, depth: depth)
                output.replaceSubrange(rowOffset..<rowOffset + compWidth, with: rowPixels)
                row += 1

            default:
                throw ReferenceDecodeError.value(
                    "Incomplete Imag frame: decoded \(row) of \(compHeight) compression rows")
            }
        }

        if row != compHeight {
            throw ReferenceDecodeError.value(
                "Incomplete Imag frame: decoded \(row) of \(compHeight) compression rows")
        }
        if alignEnd && (ptr - start) & 1 != 0 { ptr += 1 }
        return (output, ptr)
    }

    /// Copies a previously decoded row (or zeros for a forward/invalid reference).
    private static func copyRow(_ output: inout [UInt8], from referenceRow: Int, to row: Int, width: Int) {
        let destination = row * width
        if referenceRow >= 0 && referenceRow < row {
            let source = referenceRow * width
            output.replaceSubrange(destination..<destination + width, with: output[source..<source + width])
        } else {
            for index in destination..<destination + width { output[index] = 0 }
        }
    }
}
