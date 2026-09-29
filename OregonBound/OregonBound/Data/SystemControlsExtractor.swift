import Foundation

/// Recovers System 7 control artwork from a System 7.0 System file's resource
/// fork: the scrollbar CDEF 1 (its embedded monochrome bitmaps, colour-table and
/// pixs colour masks, rendered to RGB parts) and the ICON 0/1/2 alert icons.
///
/// Port of scripts/extract_system_scrollbar.py, render_system_scrollbar.py and
/// extract_system_alerts.py. Output goes under system_controls/.
enum SystemControlsExtractor {
    enum Failure: Error, CustomStringConvertible {
        case wrongScrollbarDefinition(expected: String, found: String, length: Int)
        case unexpectedBitmap(index: Int)
        case truncatedBitmap(index: Int)
        case badColorMask(resourceID: Int, reason: String)
        case wrongIconSize(resourceID: Int, length: Int)

        var description: String {
            switch self {
            case .wrongScrollbarDefinition(let expected, let found, let length):
                return "The System file's scrollbar definition (CDEF 1, \(length) bytes) is not the one on the verified System 7.0 disk (\(System7Reference.diskName)): expected SHA-256 \(expected), found \(found)"
            case .unexpectedBitmap(let index):
                return "Unexpected System 7 CDEF1 embedded bitmap (index \(index))"
            case .truncatedBitmap(let index):
                return "Truncated embedded bitmap (index \(index)) in System 7 CDEF1"
            case .badColorMask(let id, let reason):
                return "Scrollbar colour mask 'pixs' \(id) is unusable: \(reason)"
            case .wrongIconSize(let id, let length):
                return "Expected original 32x32 ICON \(id) (128 bytes); found \(length) bytes"
            }
        }
    }

    typealias RGB16 = (r: Int, g: Int, b: Int)
    typealias RGBA8 = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    /// SHA-256 of the expanded CDEF 1 code on the verified System 7.0 disk.
    static let scrollbarUnpackedSHA256 = "42e5b18afef0db0db89daa38693ac522c27805348a40b963a018d771d294882d"
    static let bitmapNames = ["up", "up_pressed", "down", "down_pressed", "left", "left_pressed",
                              "right", "right_pressed", "vertical_thumb", "horizontal_thumb"]
    /// Runtime control entry 1 can be the game's paper colour (arrow top/left bevel).
    static let gamePaper: RGB16 = (0xff00, 0xf66d, 0x8997)
    static let trackPattern: [UInt8] = [0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22]

    // MARK: Small RGBA canvas mirroring the PIL calls in render_system_scrollbar.py

    struct Canvas {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        init(width: Int, height: Int, fill: RGBA8 = (0, 0, 0, 0)) {
            self.width = width
            self.height = height
            pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height { for x in 0..<width { put(x, y, fill) } }
        }
        mutating func put(_ x: Int, _ y: Int, _ color: RGBA8) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let offset = (y * width + x) * 4
            pixels[offset] = color.r; pixels[offset + 1] = color.g; pixels[offset + 2] = color.b; pixels[offset + 3] = color.a
        }
        func get(_ x: Int, _ y: Int) -> RGBA8 {
            let offset = (y * width + x) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }
        /// Axis-aligned polyline, endpoints inclusive (PIL ImageDraw.line, width 1).
        mutating func line(_ points: [(Int, Int)], _ color: RGBA8) {
            for (a, b) in zip(points, points.dropFirst()) {
                if a.0 == b.0 {
                    for y in min(a.1, b.1)...max(a.1, b.1) { put(a.0, y, color) }
                } else if a.1 == b.1 {
                    for x in min(a.0, b.0)...max(a.0, b.0) { put(x, a.1, color) }
                } else {
                    // Bresenham for completeness; the renderer only draws axis-aligned segments.
                    var x = a.0, y = a.1
                    let dx = abs(b.0 - a.0), dy = -abs(b.1 - a.1), sx = a.0 < b.0 ? 1 : -1, sy = a.1 < b.1 ? 1 : -1
                    var error = dx + dy
                    while true {
                        put(x, y, color)
                        if x == b.0 && y == b.1 { break }
                        let doubled = 2 * error
                        if doubled >= dy { error += dy; x += sx }
                        if doubled <= dx { error += dx; y += sy }
                    }
                }
            }
        }
        /// One-pixel outline of the inclusive rectangle (PIL ImageDraw.rectangle outline).
        mutating func outline(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: RGBA8) {
            line([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], color)
        }
        mutating func paste(_ other: Canvas, at origin: (Int, Int)) {
            for y in 0..<other.height { for x in 0..<other.width { put(origin.0 + x, origin.1 + y, other.get(x, y)) } }
        }
        var image: PNGEncoder.Image { PNGEncoder.Image(width: width, height: height, colorType: .rgba, pixels: pixels) }
    }

    // MARK: CDEF 1 tables

    /// The 15 base RGB colours at CDEF1:0cd2.
    static func baseColors(_ code: BinaryReader) throws -> [RGB16] {
        try (0..<15).map { index in
            let offset = 0xcd2 + index * 6
            return (Int(try code.u16(offset)), Int(try code.u16(offset + 2)), Int(try code.u16(offset + 4)))
        }
    }

    /// Colour-table entry `index`: a base colour, or a blend of two base colours
    /// from the table at CDEF1:0d2c (CDEF1:0826–085a: unsigned multiply of the
    /// high word of ABS(delta), sign restored; division by 65536, not 65535).
    static func color(_ code: BinaryReader, index: Int, overrides: [Int: RGB16] = [:]) throws -> RGB16 {
        var bases: [Int: RGB16] = [:]
        for (i, value) in try baseColors(code).enumerated() { bases[i] = value }
        for (i, value) in overrides { bases[i] = value }
        if index < 16 {
            guard let value = bases[index] else { throw Failure.badColorMask(resourceID: 0, reason: "colour entry \(index) undefined") }
            return value
        }
        let offset = 0xd2c + (index - 16) * 6
        let first = Int(try code.u16(offset)), second = Int(try code.u16(offset + 2)), weight = Int(try code.u16(offset + 4))
        guard let a = bases[first], let b = bases[second] else {
            throw Failure.badColorMask(resourceID: 0, reason: "blend entry \(index) references undefined colours \(first)/\(second)")
        }
        func blend(_ a: Int, _ b: Int) -> Int { a + (b >= a ? 1 : -1) * ((abs(b - a) * weight * 0x1111) >> 16) }
        return (blend(a.r, b.r), blend(a.g, b.g), blend(a.b, b.b))
    }

    /// 1-bit 'pixs' mask rows (stride, bounds, depth header of 12 bytes).
    static func maskPixels(_ resource: MacResource) throws -> [[Bool]] {
        let reader = BinaryReader(resource.data)
        guard reader.count >= 12 else { throw Failure.badColorMask(resourceID: resource.id, reason: "shorter than its 12-byte header") }
        let stride = Int(try reader.u16(0) & 0x3fff)
        let top = Int(try reader.i16(2)), left = Int(try reader.i16(4)), bottom = Int(try reader.i16(6)), right = Int(try reader.i16(8))
        let depth = try reader.u16(10)
        guard depth == 1 else { throw Failure.badColorMask(resourceID: resource.id, reason: "pixel depth \(depth) is not 1") }
        let width = right - left, height = bottom - top
        guard width >= 0, height >= 0, 12 + height * stride <= reader.count, stride * 8 >= width else {
            throw Failure.badColorMask(resourceID: resource.id, reason: "bitmap bounds exceed the resource")
        }
        return (0..<height).map { y in (0..<width).map { x in reader.bytes[12 + y * stride + x / 8] & (0x80 >> UInt8(x % 8)) != 0 } }
    }

    /// The ten 16x16 monochrome bitmaps referenced from CDEF1:0db2.
    static func monochromeBitmaps(_ code: BinaryReader) throws -> [(record: [String: JSONValue], image: Canvas)] {
        var result: [(record: [String: JSONValue], image: Canvas)] = []
        for (index, name) in bitmapNames.enumerated() {
            let offset = 0xDB2 + Int(try code.i16(0xDB2 + index * 2))
            let rowBytes = Int(try code.u16(offset))
            let top = Int(try code.i16(offset + 2)), left = Int(try code.i16(offset + 4))
            let bottom = Int(try code.i16(offset + 6)), right = Int(try code.i16(offset + 8))
            let width = right - left, height = bottom - top
            guard rowBytes == 2, width == 16, height == 16 else { throw Failure.unexpectedBitmap(index: index) }
            guard offset + 10 + rowBytes * height <= code.count else { throw Failure.truncatedBitmap(index: index) }
            var image = Canvas(width: width, height: height, fill: (255, 255, 255, 255))
            for y in 0..<height {
                for x in 0..<width where code.bytes[offset + 10 + y * rowBytes + x / 8] & (0x80 >> UInt8(x % 8)) != 0 {
                    image.put(x, y, (0, 0, 0, 255))
                }
            }
            result.append((["name": .string(name), "index": .int(index), "offset": .int(offset), "row_bytes": .int(rowBytes),
                            "width": .int(width), "height": .int(height)], image))
        }
        return result
    }

    // MARK: Scrollbar

    /// Expands and verifies CDEF 1, writes system7_scrollbar_monochrome.png and
    /// system7_scrollbar.json, then renders the RGB parts and system7_scrollbar_color.json.
    static func extractScrollbar(systemFork: MacResourceFork, into output: ExtractionOutput,
                                 resourceForkSHA256: String = System7Reference.resourceForkSHA256) throws {
        let source = "The System file"
        let resource = try systemFork.require("CDEF", 1, from: source)
        let codeData = try SystemResourceDecompressor.expand(resource)
        let codeSHA = SHA256Hex.digest(codeData)
        guard codeSHA == scrollbarUnpackedSHA256 else {
            throw Failure.wrongScrollbarDefinition(expected: scrollbarUnpackedSHA256, found: codeSHA, length: codeData.count)
        }
        let code = BinaryReader(codeData)
        let bitmaps = try monochromeBitmaps(code)
        var atlas = Canvas(width: 160, height: 16)
        var records: [JSONValue] = []
        for (index, bitmap) in bitmaps.enumerated() {
            atlas.paste(bitmap.image, at: (index * 16, 0))
            var record = bitmap.record
            record["atlas_rect"] = .array([.int(index * 16), 0, 16, 16])
            records.append(.object(record))
        }
        try output.writePNG(atlas.image, to: "system_controls/system7_scrollbar_monochrome.png")

        var colorMasks: [JSONValue] = []
        var masks: [Int: MacResource] = [:]
        for index in 0..<14 {
            let offset = 0xC62 + index * 8
            let rid = Int(try code.i16(offset))
            let foreground = Int(try code.i16(offset + 2)), background = Int(try code.i16(offset + 4)), frame = Int(try code.i16(offset + 6))
            let mask = try systemFork.require("pixs", rid, from: source)
            masks[rid] = mask
            colorMasks.append(["index": .int(index), "resource_id": .int(rid), "file": .string("system7_scrollbar_pixs_\(rid).bin"),
                               "foreground_entry": .int(foreground), "background_entry": .int(background), "frame_entry": .int(frame)])
        }
        let manifest: JSONValue = [
            "source_disk_sha256": .string(System7Reference.diskSHA256),
            "source_resource_fork_sha256": .string(resourceForkSHA256),
            "source_hfs_path": .string(System7Reference.hfsPath), "resource_type": "CDEF", "resource_id": 1,
            "unpacked_sha256": .string(codeSHA), "unpacked_length": .int(codeData.count),
            "atlas_file": "system7_scrollbar_monochrome.png", "monochrome_bitmaps": .array(records),
            "color_masks": .array(colorMasks),
            "limitation": "Atlas is the monochrome CDEF branch; color masks require original drawing primitives and control color table.",
        ]
        try output.writeJSON(manifest, to: "system_controls/system7_scrollbar.json")
        try renderScrollbar(code: code, masks: masks, into: output)
    }

    private static func renderScrollbar(code: BinaryReader, masks: [Int: MacResource], into output: ExtractionOutput) throws {
        func mask(_ id: Int) throws -> [[Bool]] {
            guard let resource = masks[id] else { throw Failure.badColorMask(resourceID: id, reason: "not referenced by CDEF 1") }
            return try maskPixels(resource)
        }
        let indices = Array(0..<15) + Array(16..<38)
        var rgb16: [Int: RGB16] = [:]
        var rgba: [Int: RGBA8] = [:]
        for index in indices {
            let value = try color(code, index: index)
            rgb16[index] = value
            rgba[index] = (UInt8(value.r >> 8), UInt8(value.g >> 8), UInt8(value.b >> 8), 255)
        }
        var gameRGBA = rgba
        gameRGBA[1] = (UInt8(gamePaper.r >> 8), UInt8(gamePaper.g >> 8), UInt8(gamePaper.b >> 8), 255)
        func entry(_ palette: [Int: RGBA8], _ index: Int) -> RGBA8 { palette[index] ?? (0, 0, 0, 255) }

        var variants: [JSONValue] = []
        let states = ["normal", "pressed", "disabled"]
        for (paletteName, palette) in [("system", rgba), ("game_paper", gameRGBA)] {
            var atlas = Canvas(width: 96, height: 16)
            for (direction, ids) in [("up", (-10206, -10205)), ("down", (-10204, -10203))] {
                for (stateIndex, state) in states.enumerated() {
                    let disabled = state == "disabled", pressed = state == "pressed"
                    var part = Canvas(width: 16, height: 16, fill: entry(palette, disabled ? 32 : 33))
                    let layers: [(Int, Int?)] = [(ids.0, disabled ? 28 : pressed ? 0 : 37),
                                                 (ids.1, disabled ? nil : pressed ? 0 : 35)]
                    for (resourceID, ink) in layers {
                        guard let ink = ink else { continue }
                        for (y, row) in try mask(resourceID).enumerated() {
                            for (x, bit) in row.enumerated() where bit { part.put(x, y, entry(palette, ink)) }
                        }
                    }
                    if !disabled {
                        // CDEF1:0536–0566: inset(1,1), B20 then B50, restore rect.
                        part.line([(1, 14), (1, 1), (14, 1)], entry(palette, 1))
                        part.line([(1, 14), (14, 14), (14, 1)], entry(palette, 28))
                    }
                    part.outline(0, 0, 15, 15, entry(palette, 0))
                    let index = (direction == "up" ? 0 : 3) + stateIndex
                    atlas.paste(part, at: (index * 16, 0))
                    if paletteName == "system" {
                        variants.append(["name": .string("\(direction)_\(state)"), "rect": .array([.int(index * 16), 0, 16, 16])])
                    }
                }
            }
            try output.writePNG(atlas.image, to: "system_controls/system7_scrollbar_arrows_\(paletteName).png")
        }

        // CDEF1:0318–0392. Source thumb Rect(0,0,16,14); the rightward top pixel
        // is outside this 14px part and covered by the final control FrameRect.
        var thumb = Canvas(width: 14, height: 16, fill: entry(rgba, 18))
        thumb.line([(0, 0), (13, 0)], entry(rgba, 29))
        thumb.line([(0, 15), (0, 1), (13, 1)], entry(rgba, 34))
        thumb.line([(0, 15), (13, 15), (13, 1)], entry(rgba, 37))
        // CDEF1:0394–03be; packed InsetRect argument has dv 2, dh 3. Source and destination are both 6x10.
        for (y, row) in try mask(-10208).enumerated() {
            for (x, bit) in row.enumerated() { thumb.put(4 + x, 3 + y, entry(rgba, bit ? 36 : 34)) }
        }
        thumb.line([(4, 3), (9, 3)], entry(rgba, 35))  // CDEF1:03c2–03f2.
        try output.writePNG(thumb.image, to: "system_controls/system7_scrollbar_thumb_rgb.png")

        var track = Canvas(width: 8, height: 8)
        for y in 0..<8 { for x in 0..<8 { track.put(x, y, entry(rgba, trackPattern[y] & (0x80 >> UInt8(x)) != 0 ? 28 : 22)) } }
        try output.writePNG(track.image, to: "system_controls/system7_scrollbar_track_rgb.png")
        try output.writePNG(Canvas(width: 1, height: 1, fill: entry(rgba, 32)).image, to: "system_controls/system7_scrollbar_disabled_rgb.png")

        func rgbJSON(_ value: RGB16) -> JSONValue { [.int(value.r), .int(value.g), .int(value.b)] }
        func rgbaJSON(_ value: RGBA8) -> JSONValue { [.int(Int(value.r)), .int(Int(value.g)), .int(Int(value.b)), .int(Int(value.a))] }
        var rgb16JSON: [String: JSONValue] = [:]
        var rgba8JSON: [String: JSONValue] = [:]
        for index in indices {
            rgb16JSON[String(index)] = rgbJSON(rgb16[index] ?? (0, 0, 0))
            rgba8JSON[String(index)] = rgbaJSON(entry(rgba, index))
        }
        let manifest: JSONValue = [
            "schema_version": 1, "source": "system7_scrollbar.json",
            "rendering": "requested RGB, before device Color2Index/CLUT",
            "color_rgb16": .object(rgb16JSON), "color_rgba8": .object(rgba8JSON), "arrow_variants": .array(variants),
            "system_arrow_atlas": "system7_scrollbar_arrows_system.png",
            "game_paper_arrow_atlas": "system7_scrollbar_arrows_game_paper.png",
            "game_paper_override": ["1": rgbJSON(gamePaper)],
            "thumb": ["file": "system7_scrollbar_thumb_rgb.png", "width": 14, "height": 16],
            "track": ["file": "system7_scrollbar_track_rgb.png", "width": 8, "height": 8,
                      "pattern_hex": .string(Data(trackPattern).hexDigest), "foreground_color": 28, "background_color": 22],
            "disabled_fill": ["file": "system7_scrollbar_disabled_rgb.png", "color": 32, "rgba": rgbaJSON(entry(rgba, 32))],
            "limitations": ["No live GDevice CLUT quantization", "No RGB2Index distinguishability fallback",
                            "Game-paper variant is an explicit entry1 override, not proof of live AuxCtl table"],
        ]
        try output.writeJSON(manifest, to: "system_controls/system7_scrollbar_color.json")
    }

    // MARK: Alert icons

    /// ICON 0 (stop), 1 (note) and 2 (caution) → 32x32 RGBA PNGs plus system7_alert_icons.json.
    static func extractAlertIcons(systemFork: MacResourceFork, into output: ExtractionOutput,
                                  resourceForkSHA256: String = System7Reference.resourceForkSHA256) throws {
        var records: [JSONValue] = []
        for (id, name) in [(0, "stop"), (1, "note"), (2, "caution")] {
            let resource = try systemFork.require("ICON", id, from: "The System file")
            let bits = try SystemResourceDecompressor.expand(resource)
            guard bits.count == 128 else { throw Failure.wrongIconSize(resourceID: id, length: bits.count) }
            let bytes = [UInt8](bits)
            var image = Canvas(width: 32, height: 32, fill: (255, 255, 255, 255))
            for y in 0..<32 {
                for x in 0..<32 where bytes[y * 4 + x / 8] & (0x80 >> UInt8(x % 8)) != 0 { image.put(x, y, (0, 0, 0, 255)) }
            }
            let filename = "system7_alert_icon_\(id).png"
            try output.writePNG(image.image, to: "system_controls/\(filename)")
            records.append(["resource_id": .int(id), "name": .string(name), "width": 32, "height": 32, "file": .string(filename),
                            "attributes": .int(Int(resource.attributes)),
                            "stored_sha256": .string(SHA256Hex.digest(resource.data)),
                            "unpacked_sha256": .string(SHA256Hex.digest(bits))])
        }
        let manifest: JSONValue = [
            "source_disk_sha256": .string(System7Reference.diskSHA256),
            "source_resource_fork_sha256": .string(resourceForkSHA256),
            "source_hfs_path": .string(System7Reference.hfsPath), "icons": .array(records),
        ]
        try output.writeJSON(manifest, to: "system_controls/system7_alert_icons.json")
    }

    /// Scrollbar parts and alert icons together.
    static func extractAll(systemFork: MacResourceFork, into output: ExtractionOutput,
                           resourceForkSHA256: String = System7Reference.resourceForkSHA256) throws {
        try extractScrollbar(systemFork: systemFork, into: output, resourceForkSHA256: resourceForkSHA256)
        try extractAlertIcons(systemFork: systemFork, into: output, resourceForkSHA256: resourceForkSHA256)
    }
}
