import Foundation

/// Decodes original Macintosh NFNT strikes and FOND family records into the
/// JSON metrics and 1-bit atlases consumed by `BitmapFont`.
///
/// Port of scripts/extract_fonts.py and scripts/extract_system_fonts.py. Format
/// reference: Inside Macintosh: Text (1993), pp. 4-66–4-71, 4-91–4-95.
enum BitmapFontExtractor {
    enum Failure: Error, CustomStringConvertible {
        case truncatedTable(resourceID: Int, offset: Int, words: Int)
        case invalidRange(resourceID: Int)
        case colorFont(resourceID: Int)
        case invalidGlyphBoundaries(resourceID: Int)
        case widthTableOverlap(resourceID: Int)
        case invalidWidthTable(resourceID: Int)
        case truncatedFamily(resourceID: Int, offset: Int, words: Int)
        case associationMissing(family: String, familyID: Int, size: Int)
        case wrongSystemFont(resourceID: Int, family: String, size: Int, expected: String, found: String)

        var description: String {
            switch self {
            case .truncatedTable(let id, let offset, let words):
                return "NFNT \(id): truncated font table at byte \(offset) (\(words) words)"
            case .invalidRange(let id):
                return "NFNT \(id): invalid NFNT character range or bitmap dimensions"
            case .colorFont(let id):
                return "NFNT \(id): only original monochrome NFNT resources are supported"
            case .invalidGlyphBoundaries(let id):
                return "NFNT \(id): invalid NFNT glyph boundaries"
            case .widthTableOverlap(let id):
                return "NFNT \(id): NFNT width table overlaps glyph locations"
            case .invalidWidthTable(let id):
                return "NFNT \(id): NFNT missing-glyph metric or table terminator is invalid"
            case .truncatedFamily(let id, let offset, let words):
                return "FOND \(id): truncated font family table at byte \(offset) (\(words) words)"
            case .associationMissing(let family, let familyID, let size):
                return "FOND \(familyID) (\(family)) has no plain \(size)-point NFNT association"
            case .wrongSystemFont(let id, let family, let size, let expected, let found):
                return "NFNT \(id) (\(family) \(size)) does not match the System file from the verified System 7.0 disk (\(System7Reference.diskName)): expected SHA-256 \(expected), found \(found)"
            }
        }
    }

    static let styleNames = ["bold", "italic", "underline", "outline", "shadow", "condensed", "extended"]
    static let headerNames = [
        "font_type", "first_char", "last_char", "wid_max", "kern_max", "n_descent",
        "rect_width", "rect_height", "ow_t_loc", "ascent", "descent", "leading", "row_words",
    ]

    /// One glyph's placement metrics, kept for advance measurement.
    struct Glyph {
        let index: Int
        let code: Int?
        let missing: Bool
        let advance: Int?
    }

    /// A decoded strike: the JSON record (minus `family_associations`) and its atlas.
    struct Strike {
        let resourceID: Int
        let sourceSHA256: String
        let sourceLength: Int
        let firstChar: Int
        let lastChar: Int
        let missingGlyphIndex: Int
        let glyphs: [Glyph]
        var record: [String: JSONValue]
        /// Grayscale atlas, 255 = ink.
        let atlas: PNGEncoder.Image

        /// Sum of glyph advances for `text`, exactly as extract_fonts.render_text
        /// measures it: codes outside the strike, or unencodable characters, use
        /// the missing-character glyph.
        func advance(of text: String) -> Int {
            var pen = 0
            for character in text {
                let code = MacRoman.encode(String(character)).flatMap { $0.count == 1 ? Int($0[0]) : nil }
                pen += glyph(for: code).advance ?? 0
            }
            return pen
        }

        func glyph(for code: Int?) -> Glyph {
            if let code = code, code >= firstChar, code <= lastChar, code - firstChar < glyphs.count {
                let glyph = glyphs[code - firstChar]
                if !glyph.missing { return glyph }
            }
            return glyphs[missingGlyphIndex]
        }
    }

    struct Association {
        let size: Int
        let style: Int
        let styleNames: [String]
        let resourceID: Int
        let depth: Int
        var record: JSONValue {
            ["size": .int(size), "style": .int(style), "style_names": .array(styleNames.map { .string($0) }),
             "resource_id": .int(resourceID), "depth": .int(depth)]
        }
    }

    struct Family {
        let resourceID: Int
        let familyID: Int
        let name: String
        let associations: [Association]
        let record: JSONValue
    }

    private static func words(_ reader: BinaryReader, _ offset: Int, _ count: Int, resourceID: Int, family: Bool = false) throws -> [Int] {
        guard offset >= 0, count >= 0, offset + count * 2 <= reader.count else {
            throw family ? Failure.truncatedFamily(resourceID: resourceID, offset: offset, words: count)
                         : Failure.truncatedTable(resourceID: resourceID, offset: offset, words: count)
        }
        return (0..<count).map { Int(reader.bytes[offset + $0 * 2]) << 8 | Int(reader.bytes[offset + $0 * 2 + 1]) }
    }

    /// Decodes an NFNT resource into metrics and a mode-1 style atlas (set bits are ink).
    static func parseNFNT(_ data: Data, resourceID: Int) throws -> Strike {
        let reader = BinaryReader(data)
        var values = try words(reader, 0, 13, resourceID: resourceID)
        for index in [4, 5, 11] where values[index] & 0x8000 != 0 { values[index] -= 0x10000 }  // kern_max, n_descent, leading
        var header: [String: JSONValue] = [:]
        for (name, value) in zip(headerNames, values) { header[name] = .int(value) }
        let fontType = values[0], first = values[1], last = values[2]
        let kernMax = values[4], nDescent = values[5], height = values[7], owTLoc = values[8]
        let ascent = values[9], rowWords = values[12]
        guard first >= 0, first <= last, last <= 255, height != 0, rowWords != 0 else {
            throw Failure.invalidRange(resourceID: resourceID)
        }
        guard fontType & 0x0c == 0 else { throw Failure.colorFont(resourceID: resourceID) }
        let rowBytes = rowWords * 2
        let bitmapEnd = 26 + rowBytes * height
        let count = last - first + 1
        let locations = try words(reader, bitmapEnd, count + 2, resourceID: resourceID)
        guard locations == locations.sorted(), let lastLocation = locations.last, lastLocation <= rowWords * 16 else {
            throw Failure.invalidGlyphBoundaries(resourceID: resourceID)
        }
        // owTLoc counts words from the owTLoc field at byte 16, not from byte 0.
        // Positive nDescent supplies its high word for large strikes.
        let offsetWords = owTLoc + (max(0, nDescent) << 16)
        let widthOffset = 16 + 2 * offsetWords
        guard widthOffset >= bitmapEnd + (count + 2) * 2 else { throw Failure.widthTableOverlap(resourceID: resourceID) }
        // System 7 Geneva 9/12 end immediately after the missing-glyph metric,
        // without the sentinel present in Chicago and WTTimes.
        let omittedTerminator = fontType & 3 == 0 && reader.count == widthOffset + (count + 1) * 2
        let widthCount = count + (omittedTerminator ? 1 : 2)
        let widths = try words(reader, widthOffset, widthCount, resourceID: resourceID)
        guard let lastWidth = widths.last, widths[count] != 0xffff, omittedTerminator || lastWidth == 0xffff else {
            throw Failure.invalidWidthTable(resourceID: resourceID)
        }
        var tableEnd = widthOffset + widthCount * 2
        var fractionalWidths: [Int]?
        var imageHeights: [Int]?
        if fontType & 2 != 0 {
            fractionalWidths = try words(reader, tableEnd, count + 2, resourceID: resourceID)
            tableEnd += (count + 2) * 2
        }
        if fontType & 1 != 0 {
            imageHeights = try words(reader, tableEnd, count + 2, resourceID: resourceID)
            tableEnd += (count + 2) * 2
        }

        let atlasWidth = rowWords * 16
        var pixels = [UInt8](repeating: 0, count: atlasWidth * height)
        for y in 0..<height {
            let rowStart = 26 + y * rowBytes
            for x in 0..<atlasWidth where reader.bytes[rowStart + x / 8] & (0x80 >> UInt8(x % 8)) != 0 {
                pixels[y * atlasWidth + x] = 255
            }
        }
        let atlas = PNGEncoder.Image(width: atlasWidth, height: height, colorType: .grayscale, pixels: pixels)

        var glyphs: [Glyph] = []
        var glyphRecords: [JSONValue] = []
        for index in 0...count {
            let code: Int? = index < count ? first + index : nil
            let word = widths[index]
            let missing = word == 0xffff
            let advance: Int? = missing ? nil : word & 255
            glyphs.append(Glyph(index: index, code: code, missing: missing, advance: advance))
            var record: [String: JSONValue] = [
                "index": .int(index),
                "code": code.map { .int($0) } ?? .null,
                "character": code.map { .string(MacRoman.decode([UInt8($0)])) } ?? .null,
                "missing": .bool(missing),
                "atlas_rect": .array([.int(locations[index]), 0, .int(locations[index + 1] - locations[index]), .int(height)]),
                "offset_width_word": .int(word),
                "bearing_x": missing ? .null : .int((word >> 8) + kernMax),
                "bearing_y": .int(-ascent),
                "advance": advance.map { .int($0) } ?? .null,
            ]
            if let fractionalWidths = fractionalWidths { record["advance_8_8"] = .int(fractionalWidths[index]) }
            if let imageHeights = imageHeights {
                record["image_top"] = .int(imageHeights[index] >> 8)
                record["image_height"] = .int(imageHeights[index] & 255)
            }
            glyphRecords.append(.object(record))
        }
        let sha = SHA256Hex.digest(data)
        let record: [String: JSONValue] = [
            "schema_version": 1, "resource_type": "NFNT", "resource_id": .int(resourceID),
            "source_sha256": .string(sha), "source_length": .int(reader.count),
            "encoding": "mac_roman", "header": .object(header),
            "atlas": ["file": .string("nfnt_\(resourceID).png"), "width": .int(atlasWidth),
                      "height": .int(height), "mode": "1", "ink_value": 255,
                      "background_value": 0, "bit_order": "MSB first"],
            "table_offsets": ["bitmap": 26, "locations": .int(bitmapEnd), "widths": .int(widthOffset),
                              "parsed_end": .int(tableEnd)],
            "location_table": .array(locations.map { .int($0) }),
            "offset_width_table": .array(widths.map { .int($0) }),
            "fractional_width_table": fractionalWidths.map { .array($0.map { .int($0) }) } ?? .null,
            "image_height_table": imageHeights.map { .array($0.map { .int($0) }) } ?? .null,
            "missing_glyph_index": .int(count),
            "glyphs": .array(glyphRecords),
            "trailing_bytes_hex": .string(Data(reader.bytes[min(tableEnd, reader.count)...]).hexDigest),
        ]
        return Strike(resourceID: resourceID, sourceSHA256: sha, sourceLength: reader.count, firstChar: first, lastChar: last,
                      missingGlyphIndex: count, glyphs: glyphs, record: record, atlas: atlas)
    }

    /// Decodes the 52-byte FamRec and its required font association table.
    static func parseFOND(_ data: Data, resourceID: Int, name: String) throws -> Family {
        let reader = BinaryReader(data)
        let header = try words(reader, 0, 26, resourceID: resourceID, family: true)
        let count = try words(reader, 52, 1, resourceID: resourceID, family: true)[0] + 1
        let entries = try words(reader, 54, count * 3, resourceID: resourceID, family: true)
        var associations: [Association] = []
        for index in 0..<count {
            let size = entries[index * 3], style = entries[index * 3 + 1], fontID = entries[index * 3 + 2]
            let names = styleNames.enumerated().compactMap { style & (1 << $0.offset) != 0 ? $0.element : nil }
            associations.append(Association(size: size, style: style, styleNames: names.isEmpty ? ["plain"] : names,
                                            resourceID: fontID < 0x8000 ? fontID : fontID - 0x10000,
                                            depth: 1 << ((style >> 8) & 3)))
        }
        let record: JSONValue = [
            "resource_type": "FOND", "resource_id": .int(resourceID), "name": .string(name),
            "source_sha256": .string(SHA256Hex.digest(data)), "source_length": .int(reader.count),
            "flags": .int(header[0]), "family_id": .int(header[1]), "version": .int(header[25]),
            "first_char": .int(header[2]), "last_char": .int(header[3]),
            "width_table_offset": .int(Int(try reader.u32(16))),
            "kerning_table_offset": .int(Int(try reader.u32(20))),
            "style_table_offset": .int(Int(try reader.u32(24))),
            "style_properties_4_12": .array(header[14..<23].map { .int($0) }),
            "associations": .array(associations.map { $0.record }),
        ]
        return Family(resourceID: resourceID, familyID: header[1], name: name, associations: associations, record: record)
    }

    private static func familyAssociation(_ family: Family, _ association: Association) -> JSONValue {
        guard case .object(var fields) = association.record else { return association.record }
        fields["family_id"] = .int(family.familyID)
        fields["family_name"] = .string(family.name)
        return .object(fields)
    }

    /// Writes fonts/nfnt_<id>.json, fonts/nfnt_<id>.png and fonts/manifest.json for
    /// every NFNT in the game's resource fork. `sourceName` and `sourceSHA256`
    /// describe the fork file the manifest records (the reference pipeline hashed
    /// raw/oregon_trail.rsrc); pass nil to omit the hash.
    @discardableResult
    static func extractGameFonts(trailFork: MacResourceFork, into output: ExtractionOutput,
                                 sourceName: String = "raw/oregon_trail.rsrc", sourceSHA256: String? = nil) throws -> JSONValue {
        var families: [Family] = []
        for resource in trailFork.resources where resource.type == "FOND" {
            families.append(try parseFOND(resource.data, resourceID: resource.id, name: resource.name ?? ""))
        }
        var fonts: [JSONValue] = []
        for resource in trailFork.resources(ofType: "NFNT") {
            var strike = try parseNFNT(resource.data, resourceID: resource.id)
            let associations: [JSONValue] = families.flatMap { family in
                family.associations.filter { $0.resourceID == resource.id }.map { familyAssociation(family, $0) }
            }
            strike.record["family_associations"] = .array(associations)
            try output.writePNG(strike.atlas, to: "fonts/nfnt_\(resource.id).png")
            try output.writeJSON(JSONValue.object(strike.record), to: "fonts/nfnt_\(resource.id).json")
            let sampleAdvance = strike.advance(of: "NFNT \(resource.id)  The Oregon Trail  ABC xyz 0123456789")
            fonts.append(["resource_id": .int(resource.id), "metrics_file": .string("nfnt_\(resource.id).json"),
                          "atlas_file": .string("nfnt_\(resource.id).png"), "sample_advance": .int(sampleAdvance),
                          "family_associations": .array(associations)])
        }
        let manifest: JSONValue = ["schema_version": 1, "source": .string(sourceName),
                                   "source_sha256": sourceSHA256.map { .string($0) } ?? .null,
                                   "families": .array(families.map { $0.record }), "fonts": .array(fonts)]
        try output.writeJSON(manifest, to: "fonts/manifest.json")
        return manifest
    }

    /// The strikes the game borrows from the System file, resolved through the
    /// FOND association tables, with the SHA-256 of each NFNT on the verified
    /// System 7.0 disk.
    struct SystemSelection {
        let familyID: Int
        let familyName: String
        let size: Int
        let expectedSHA256: String
    }

    static let systemSelections = [
        SystemSelection(familyID: 0, familyName: "Chicago", size: 12,
                        expectedSHA256: "36157cec9b4fc731994ca93a7b3749dc9a8e2c24e6460f9b296cf98b45405852"),
        SystemSelection(familyID: 3, familyName: "Geneva", size: 9,
                        expectedSHA256: "b2bbba4a4cd1e78320c6a4256bd5d08e01326349804905a1e5d577521f03c754"),
        SystemSelection(familyID: 3, familyName: "Geneva", size: 12,
                        expectedSHA256: "1ae070fb30e3f9912eec605f023db2ca5919624ad898570d8aa12b3e65fec916"),
    ]

    /// Writes Chicago 12, Geneva 9 and Geneva 12 (fonts/nfnt_<id>.json/.png) and
    /// fonts/system_font_manifest.json from a System 7.0 System file's resource fork.
    @discardableResult
    static func extractSystemFonts(systemFork: MacResourceFork, into output: ExtractionOutput,
                                   resourceForkSHA256: String = System7Reference.resourceForkSHA256) throws -> JSONValue {
        let source = "The System file"
        var familyOrder: [Int] = []
        var families: [Int: Family] = [:]
        var fonts: [JSONValue] = []
        for selection in systemSelections {
            let familyResource = try systemFork.require("FOND", selection.familyID, from: source)
            let family = try parseFOND(try SystemResourceDecompressor.expand(familyResource),
                                       resourceID: selection.familyID, name: selection.familyName)
            guard let association = family.associations.first(where: { $0.size == selection.size && $0.style == 0 }) else {
                throw Failure.associationMissing(family: selection.familyName, familyID: selection.familyID, size: selection.size)
            }
            let fontResource = try systemFork.require("NFNT", association.resourceID, from: source)
            let data = try SystemResourceDecompressor.expand(fontResource)
            let sha = SHA256Hex.digest(data)
            guard sha == selection.expectedSHA256 else {
                throw Failure.wrongSystemFont(resourceID: association.resourceID, family: selection.familyName,
                                              size: selection.size, expected: selection.expectedSHA256, found: sha)
            }
            var strike = try parseNFNT(data, resourceID: association.resourceID)
            let associations: JSONValue = .array([familyAssociation(family, association)])
            strike.record["family_associations"] = associations
            strike.record["provenance"] = "system_font_manifest.json"
            try output.writeJSON(JSONValue.object(strike.record), to: "fonts/nfnt_\(association.resourceID).json")
            try output.writePNG(strike.atlas, to: "fonts/nfnt_\(association.resourceID).png")
            if families[selection.familyID] == nil { familyOrder.append(selection.familyID) }
            families[selection.familyID] = family
            fonts.append(["resource_id": .int(association.resourceID),
                          "metrics_file": .string("nfnt_\(association.resourceID).json"),
                          "atlas_file": .string("nfnt_\(association.resourceID).png"),
                          "sample_advance": .int(strike.advance(of: "Move   Stop Hunting")),
                          "source_sha256": .string(sha), "source_length": .int(data.count),
                          "family_associations": associations])
        }
        let manifest: JSONValue = [
            "schema_version": 1, "source_url": .string(System7Reference.sourceURL),
            "disk_sha256": .string(System7Reference.diskSHA256),
            "source_revision": .string(System7Reference.sourceRevision),
            "disk_length": .int(System7Reference.diskLength), "hfs_path": .string(System7Reference.hfsPath),
            "resource_fork_sha256": .string(resourceForkSHA256),
            "families": .array(familyOrder.compactMap { families[$0]?.record }), "fonts": .array(fonts),
        ]
        try output.writeJSON(manifest, to: "fonts/system_font_manifest.json")
        return manifest
    }
}
