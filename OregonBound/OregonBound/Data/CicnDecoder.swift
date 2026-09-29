import Foundation

// Port of scripts/graphics_extract/cicn.py: color icon → RGBA, with the
// 1-bit mask supplying alpha.

enum CicnDecoder {
    /// cicn.decode_cicn.
    static func decode(resource: ResourceInfo, data: Data) -> [DecodedImage] {
        let source = ByteSource(data)
        var diagnostics: [DecodeDiagnostic] = []
        do {
            try QuickDrawColorTable.requireAvailable(source, 0, 50, "cicn PixMap")
            let pixmap = try QuickDrawPixMap(parsing: source, at: QuickDrawPixMap.cicnOffset)
            let width = pixmap.width
            let height = pixmap.height
            let rowBytes = pixmap.rowBytes
            let pixelSize = pixmap.pixelSize
            if width <= 0 || height <= 0 {
                throw ReferenceDecodeError.value("Invalid cicn dimensions: \(width)x\(height)")
            }

            var offset = 50
            try QuickDrawColorTable.requireAvailable(source, offset, 14, "cicn mask bitmap")
            let maskRowBytes = Int(try source.u16(offset + 4))
            let maskBounds = try source.rect(offset + 6)
            let maskHeight = maskBounds.height
            offset += 14

            try QuickDrawColorTable.requireAvailable(source, offset, 14, "cicn black-and-white bitmap")
            let bwRowBytes = Int(try source.u16(offset + 4))
            let bwBounds = try source.rect(offset + 6)
            let bwHeight = bwBounds.height
            offset += 14

            try QuickDrawColorTable.requireAvailable(source, offset, 4, "cicn icon data handle")
            offset += 4

            let maskDataStart = offset
            let maskDataLength = maskRowBytes * maskHeight
            try QuickDrawColorTable.requireAvailable(source, offset, maskDataLength, "cicn mask data")
            let maskData = source.slice(offset, offset + maskDataLength)
            offset += maskDataLength

            let bwDataLength = bwRowBytes * bwHeight
            try QuickDrawColorTable.requireAvailable(source, offset, bwDataLength, "cicn black-and-white data")
            offset += bwDataLength

            let colorTableStart = offset
            let (colorsByValue, colorSpecCount) = try QuickDrawColorTable.parseByValue(source, at: offset)
            let colorTableLength = 8 + colorSpecCount * 8
            offset += colorTableLength

            let pixelDataStart = offset
            let pixelDataLength = rowBytes * height
            try QuickDrawColorTable.requireAvailable(source, offset, pixelDataLength, "cicn pixel data")
            let pixelData = source.slice(offset, offset + pixelDataLength)

            // Color lookups first, then alpha, exactly as the reference orders them.
            guard pixelSize != 0 else { throw ReferenceDecodeError.divisionByZero }
            let pixelsPerByte = 8 / pixelSize
            guard pixelsPerByte != 0 else { throw ReferenceDecodeError.divisionByZero }
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for row in 0..<height {
                let rowStart = row * rowBytes
                for column in 0..<width {
                    let byteIndex = rowStart + column / pixelsPerByte
                    guard byteIndex < pixelData.count else { throw ReferenceDecodeError.indexOutOfRange }
                    let value = try extractBits(pixelData[pixelData.startIndex + byteIndex], column: column, pixelSize: pixelSize)
                    let color = colorsByValue[UInt16(value)] ?? RGBColor(red: 0, green: 0, blue: 0)
                    let target = (row * width + column) * 4
                    rgba[target] = color.red
                    rgba[target + 1] = color.green
                    rgba[target + 2] = color.blue
                }
            }
            for row in 0..<height {
                let rowStart = row * maskRowBytes
                for column in 0..<width {
                    let byteIndex = rowStart + column / 8
                    guard byteIndex < maskData.count else { throw ReferenceDecodeError.indexOutOfRange }
                    let bit = (maskData[maskData.startIndex + byteIndex] >> UInt8(7 - column % 8)) & 1
                    rgba[(row * width + column) * 4 + 3] = bit != 0 ? 255 : 0
                }
            }

            if maskBounds.left != 0 || maskBounds.width != width {
                diagnostics.append(DecodeDiagnostic("warning", "cicn.mask_bounds", "Mask bounds differ from PixMap width"))
            }

            let image = PNGEncoder.Image(width: width, height: height, colorType: .rgba, pixels: rgba)
            return [DecodedImage(
                resource: resource,
                status: diagnostics.isEmpty ? .ok : .partial,
                imagePath: nil,
                width: width,
                height: height,
                mode: "RGBA",
                frameIndex: 0,
                frameCount: 1,
                palette: PaletteInfo(source: "cicn_ctable", entryCount: colorSpecCount),
                byteRanges: [
                    "mask": [maskDataStart, maskDataStart + maskData.count],
                    "color_table": [colorTableStart, colorTableStart + colorTableLength],
                    "pixels": [pixelDataStart, pixelDataStart + pixelData.count],
                ],
                diagnostics: diagnostics,
                image: image)]
        } catch {
            return [DecodedImage.failed(
                resource, diagnostics: [DecodeDiagnostic("error", "cicn.decode_failed", "\(error)")])]
        }
    }

    /// cicn._extract_bits: the `column`th pixel of a packed byte.
    static func extractBits(_ byte: UInt8, column: Int, pixelSize: Int) throws -> Int {
        switch pixelSize {
        case 1: return Int(byte >> UInt8(7 - column % 8)) & 0x01
        case 2: return Int(byte >> UInt8(6 - (column % 4) * 2)) & 0x03
        case 4: return Int(byte >> UInt8(4 - (column % 2) * 4)) & 0x0F
        case 8: return Int(byte)
        default: throw ReferenceDecodeError.value("Unsupported pixel_size: \(pixelSize)")
        }
    }
}
