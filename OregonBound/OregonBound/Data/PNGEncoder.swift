import Foundation

/// Minimal deterministic PNG writer. Indexed output keeps the original palette
/// indices so consumers can substitute colors by index, as the game does.
enum PNGEncoder {
    enum ColorType: UInt8 { case grayscale = 0, rgb = 2, indexed = 3, rgba = 6 }

    struct Image {
        let width: Int
        let height: Int
        let colorType: ColorType
        /// Packed 8-bit samples, row-major, `width * channels` bytes per row.
        let pixels: [UInt8]
        /// RGB triples; only for `.indexed`. Padded to 256 entries when shorter.
        var palette: [UInt8] = []
        /// Optional per-index alpha (tRNS) for indexed images.
        var transparency: [UInt8]? = nil
    }

    static func encode(_ image: Image) throws -> Data {
        let channels: Int
        switch image.colorType {
        case .grayscale, .indexed: channels = 1
        case .rgb: channels = 3
        case .rgba: channels = 4
        }
        precondition(image.pixels.count == image.width * image.height * channels, "PNG pixel buffer size mismatch")
        var raw = Data(capacity: (image.width * channels + 1) * image.height)
        let stride = image.width * channels
        for row in 0..<image.height {
            raw.append(0)  // filter type: none
            raw.append(contentsOf: image.pixels[row * stride..<(row + 1) * stride])
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendU32(UInt32(image.width)); header.appendU32(UInt32(image.height))
        header.append(contentsOf: [8, image.colorType.rawValue, 0, 0, 0])
        png.append(chunk("IHDR", header))
        if image.colorType == .indexed {
            var palette = image.palette
            if palette.count < 256 * 3 { palette += [UInt8](repeating: 0, count: 256 * 3 - palette.count) }
            png.append(chunk("PLTE", Data(palette.prefix(256 * 3))))
            if let transparency = image.transparency { png.append(chunk("tRNS", Data(transparency))) }
        }
        png.append(chunk("IDAT", try Zlib.compress(raw)))
        png.append(chunk("IEND", Data()))
        return png
    }

    private static func chunk(_ type: String, _ body: Data) -> Data {
        var chunk = Data()
        chunk.appendU32(UInt32(body.count))
        var typed = Data(type.utf8)
        typed.append(body)
        chunk.append(typed)
        chunk.appendU32(CRC32.checksum(typed))
        return chunk
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

enum Zlib {
    enum Failure: Error { case compressionFailed }
    /// zlib-wrapped DEFLATE: Foundation supplies the raw stream, we add the header and Adler-32.
    static func compress(_ data: Data) throws -> Data {
        var out = Data([0x78, 0xDA])
        if data.isEmpty {
            out.append(contentsOf: [0x03, 0x00])
        } else {
            guard let deflated = try? (data as NSData).compressed(using: .zlib) as Data else { throw Failure.compressionFailed }
            out.append(deflated)
        }
        out.appendU32(adler32(data))
        return out
    }
    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }
}
