import Foundation

/// Decodes the game's text-bearing resources into the JSON files read by
/// `OriginalResources`, `OriginalOpeningView` and `OriginalMap`:
/// STR# → strings/str_<id>.json, WST# → guidebook/wst_<id>.json,
/// DITL → dialogs/ditl_<id>.json, HVof → map_viewports/hvof_<id>.json and
/// ORGN → metadata/orgn.json.
///
/// Port of scripts/extract_str.py, extract_wst.py, extract_ditl.py and extract_hvof.py,
/// including their tolerance of short resources (a truncated list simply ends early).
enum TextResourceExtractors {
    enum Failure: Error, CustomStringConvertible {
        case noOriginResource
        var description: String {
            switch self { case .noOriginResource: return "The game file contains no ORGN version resource" }
        }
    }

    // MARK: STR#

    /// 2-byte count followed by Pascal strings. Runs out of data gracefully.
    static func parseSTR(_ data: Data, resourceID: Int) -> JSONValue {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return ["id": .int(resourceID), "count": 0, "strings": []] }
        let count = Int(bytes[0]) << 8 | Int(bytes[1])
        var strings: [JSONValue] = []
        var position = 2
        for _ in 0..<count {
            guard position < bytes.count else { break }
            let length = Int(bytes[position])
            position += 1
            strings.append(.string(MacRoman.decode(bytes[position..<min(position + length, bytes.count)])))
            position += length
        }
        return ["id": .int(resourceID), "count": .int(count), "strings": .array(strings)]
    }

    // MARK: WST#

    /// MECC guidebook text: 2-byte declared count, then 0x01-delimited entries of
    /// one style byte plus Mac Roman text; trailing NULs are stripped and empty
    /// entries skipped. `entry_count` is the number of entries actually found.
    static func parseWST(_ data: Data, resourceID: Int, name: String?) -> JSONValue {
        let nameValue: JSONValue = name.map { .string($0) } ?? .null
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return ["id": .int(resourceID), "name": nameValue, "entry_count": 0, "entries": []] }
        var entries: [JSONValue] = []
        for part in bytes[2...].split(separator: 0x01, omittingEmptySubsequences: true) {
            var text = part.dropFirst()
            while text.last == 0 { text = text.dropLast() }
            guard !text.isEmpty else { continue }
            let decoded = MacRoman.decode(text)
            guard !decoded.isEmpty else { continue }
            entries.append(["index": .int(entries.count), "text": .string(decoded)])
        }
        return ["id": .int(resourceID), "name": nameValue, "entry_count": .int(entries.count), "entries": .array(entries)]
    }

    // MARK: DITL

    static let dialogItemTypeNames: [Int: String] = [
        0: "userItem", 4: "button", 5: "checkbox", 6: "radio", 7: "control",
        8: "staticText", 16: "editText", 32: "icon", 64: "picture",
    ]
    /// Item types whose data field is a 2-byte resource ID.
    static let resourceIDItemTypes: Set<Int> = [7, 32, 64]

    /// Dialog item list: (count - 1), then per item a 4-byte placeholder, bounds
    /// Rect, type byte (bit 7 = disabled), data length and even-padded data.
    static func parseDITL(_ data: Data, resourceID: Int) -> JSONValue {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return ["id": .int(resourceID), "item_count": 0, "items": []] }
        let itemCount = (Int(bytes[0]) << 8 | Int(bytes[1])) + 1
        var items: [JSONValue] = []
        var position = 2
        func i16(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]))) }
        for _ in 0..<itemCount {
            guard position + 14 <= bytes.count else { break }
            position += 4
            let top = i16(position), left = i16(position + 2), bottom = i16(position + 4), right = i16(position + 6)
            position += 8
            let typeByte = Int(bytes[position])
            position += 1
            let disabled = typeByte & 0x80 != 0
            let typeCode = typeByte & 0x7F
            let typeName = dialogItemTypeNames[typeCode] ?? "unknown_\(typeCode)"
            let dataLength = Int(bytes[position])
            position += 1
            let raw = bytes[position..<min(position + dataLength, bytes.count)]
            position += dataLength + dataLength % 2
            let decoded: JSONValue
            if resourceIDItemTypes.contains(typeCode) {
                decoded = raw.count >= 2 ? .int(Int(raw[raw.startIndex]) << 8 | Int(raw[raw.startIndex + 1])) : .null
            } else {
                decoded = .string(MacRoman.decode(raw))
            }
            items.append(["type": .string(typeName), "disabled": .bool(disabled),
                          "bounds": ["top": .int(top), "left": .int(left), "bottom": .int(bottom), "right": .int(right)],
                          "data": decoded])
        }
        return ["id": .int(resourceID), "item_count": .int(itemCount), "items": .array(items)]
    }

    // MARK: HVof

    /// Map viewport scroll offsets: signed byte pairs (dx, dy); an odd trailing byte is ignored.
    static func parseHVof(_ data: Data, resourceID: Int, name: String?) -> JSONValue {
        let bytes = [UInt8](data)
        let pairCount = bytes.count / 2
        let points: [JSONValue] = (0..<pairCount).map {
            ["dx": .int(Int(Int8(bitPattern: bytes[$0 * 2]))), "dy": .int(Int(Int8(bitPattern: bytes[$0 * 2 + 1])))]
        }
        return ["id": .int(resourceID), "name": name.map { .string($0) } ?? .null,
                "point_count": .int(pairCount), "points": .array(points)]
    }

    // MARK: ORGN

    /// Version/copyright text, stripped of leading and trailing whitespace the
    /// way Python's str.strip() does.
    static func parseORGN(_ data: Data, resourceID: Int, sourceFile: String) -> JSONValue {
        let text = MacRoman.decode(data)
        let trimmed = String(String(text.drop(while: isPythonWhitespace)).reversed().drop(while: isPythonWhitespace).reversed())
        return ["id": .int(resourceID), "text": .string(trimmed), "source_file": .string(sourceFile)]
    }

    private static func isPythonWhitespace(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x09...0x0D, 0x1C...0x1F, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    // MARK: Writers

    static func extractStrings(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in trailFork.resources(ofType: "STR#") {
            try output.writeJSON(parseSTR(resource.data, resourceID: resource.id), to: "strings/str_\(resource.id).json")
        }
    }

    static func extractGuidebook(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in trailFork.resources(ofType: "WST#") {
            try output.writeJSON(parseWST(resource.data, resourceID: resource.id, name: resource.name),
                                 to: "guidebook/wst_\(resource.id).json")
        }
    }

    static func extractDialogs(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in trailFork.resources(ofType: "DITL") {
            try output.writeJSON(parseDITL(resource.data, resourceID: resource.id), to: "dialogs/ditl_\(resource.id).json")
        }
    }

    static func extractMapViewports(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in trailFork.resources(ofType: "HVof") {
            try output.writeJSON(parseHVof(resource.data, resourceID: resource.id, name: resource.name),
                                 to: "map_viewports/hvof_\(resource.id).json")
        }
    }

    /// Writes metadata/orgn.json from the first ORGN resource. `sourceFile` is the
    /// recorded provenance string; the reference pipeline wrote "raw/oregon_trail.rsrc".
    static func extractOrigin(trailFork: MacResourceFork, into output: ExtractionOutput,
                              sourceFile: String = "raw/oregon_trail.rsrc") throws {
        guard let resource = trailFork.resources.first(where: { $0.type == "ORGN" }) else { throw Failure.noOriginResource }
        try output.writeJSON(parseORGN(resource.data, resourceID: resource.id, sourceFile: sourceFile), to: "metadata/orgn.json")
    }

    /// Runs every text extractor above.
    static func extractAll(trailFork: MacResourceFork, into output: ExtractionOutput,
                           originSourceFile: String = "raw/oregon_trail.rsrc") throws {
        try extractStrings(trailFork: trailFork, into: output)
        try extractGuidebook(trailFork: trailFork, into: output)
        try extractDialogs(trailFork: trailFork, into: output)
        try extractMapViewports(trailFork: trailFork, into: output)
        try extractOrigin(trailFork: trailFork, into: output, sourceFile: originSourceFile)
    }
}
