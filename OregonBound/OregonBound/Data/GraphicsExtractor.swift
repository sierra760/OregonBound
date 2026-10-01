import Foundation

// Port of scripts/extract_graphics.py (driver), scripts/graphics_extract/
// exporter.py (output layout), validation.py and models.py. Output paths and
// manifest values match the reference pipeline; contact sheets are skipped.

enum GraphicsExtractor {
    static let graphicalTypes: Set<String> = ["Imag", "Ima4", "cicn", "PICT", "clut"]
    struct PaletteContext { let bytes: [UInt8]; let source: String }
    enum Failure: Error, CustomStringConvertible {
        case incomplete(String)
        var description: String { switch self { case .incomplete(let detail): return "Graphics extraction failed: " + detail } }
    }
    static let sourceFileName = "oregon_color"
    static let expectedOregonColorCounts: [(type: String, count: Int)] = [
        ("Imag", 33), ("PICT", 1), ("cicn", 24), ("clut", 2),
    ]

    /// extract_graphics.extract + exporter.write_outputs: decode every
    /// graphical resource in `colorFork`, write `images/<Type>/<png>`,
    /// `graphics_manifest.json` at the output root and `diagnostics/summary.json`.
    static func extract(colorFork: MacResourceFork, into output: ExtractionOutput,
                        sourceName: String = sourceFileName,
                        paletteContext: PaletteContext? = nil,
                        expectedCounts: [(type: String, count: Int)] = expectedOregonColorCounts,
                        emptyPlaceholders: Set<GameDataSourceCatalog.ResourceIdentity> = [],
                        strict: Bool = false) throws -> GraphicsManifestDocument {
        let localPalette = try ImagDecoder.fallbackPalette(from: colorFork)
        let fallbackPalette = paletteContext?.bytes ?? localPalette.palette
        let fallbackSource = paletteContext?.source ?? localPalette.source
        let records = colorFork.resources.filter { graphicalTypes.contains($0.type) }
        var manifest = GraphicsManifestDocument(sourceFile: sourceName)
        manifest.palettes = paletteRecords(records, sourceFile: sourceName)

        for record in records {
            if emptyPlaceholders.contains(.init(type: record.type, id: record.id)) {
                guard ["Imag", "Ima4"].contains(record.type), record.data == Data([0, 0]) else {
                    throw Failure.incomplete("Invalid placeholder \(record.type) \(record.id)")
                }
                continue
            }
            let info = resourceInfo(record, sourceFile: sourceName)
            switch record.type {
            case "Imag", "Ima4":
                manifest.images += ImagDecoder.decode(resource: info, data: record.data,
                                                      fallbackPalette: fallbackPalette, fallbackSource: fallbackSource)
            case "cicn":
                manifest.images += CicnDecoder.decode(resource: info, data: record.data)
            case "PICT":
                manifest.images.append(PICTDecoder.convert(resource: info, data: record.data))
            default:
                break
            }
        }

        manifest.diagnostics += validate(manifest, strict: strict, expectedCounts: expectedCounts)
        if strict {
            let diagnostics = manifest.diagnostics + manifest.images.flatMap(\.diagnostics) + manifest.palettes.flatMap(\.diagnostics)
            let unacceptable = diagnostics.filter {
                $0.severity == "error" || ($0.severity == "warning" && $0.code != "imag.palette_fallback")
            }
            if let first = unacceptable.first { throw Failure.incomplete(first.message) }
            if manifest.images.contains(where: { $0.image == nil }) { throw Failure.incomplete("Missing decoded pixels") }
        }
        try writeOutputs(&manifest, into: output)
        return manifest
    }

    /// extract_pict_text.py: the four text-only PICTs the app draws with the
    /// original bitmap fonts, as `pictures/pict_<id>.json`.
    static let textPictureIds = [2050, 2051, 2052, 2070]

    static func extractTextPictures(trailFork: MacResourceFork, into output: ExtractionOutput) throws {
        for resource in trailFork.resources where resource.type == "PICT" && textPictureIds.contains(resource.id) {
            let picture = try TextPictureDecoder.decode(resource.data, resourceId: resource.id)
            try output.writeJSON(picture, to: "pictures/pict_\(resource.id).json")
        }
    }

    // MARK: - Pieces

    /// resource_reader.read_resources: manifest identity for one resource.
    static func resourceInfo(_ resource: MacResource, sourceFile: String = sourceFileName) -> ResourceInfo {
        ResourceInfo(sourceFile: sourceFile, resourceType: resource.type, resourceId: resource.id,
                     name: resource.name ?? "", rawLength: resource.data.count)
    }

    /// extract_graphics.build_palette_records.
    static func paletteRecords(_ records: [MacResource], sourceFile: String = sourceFileName) -> [PaletteRecord] {
        var palettes: [PaletteRecord] = []
        for record in records where record.type == "clut" {
            let info = resourceInfo(record, sourceFile: sourceFile)
            do {
                let colors = try QuickDrawColorTable.parse(ByteSource(record.data), at: 0)
                palettes.append(PaletteRecord(
                    resource: info,
                    palette: PaletteInfo(source: "clut", entryCount: colors.count, resourceId: record.id),
                    colors: colors))
            } catch {
                palettes.append(PaletteRecord(
                    resource: info,
                    palette: PaletteInfo(source: "clut", entryCount: 0, resourceId: record.id),
                    colors: [],
                    diagnostics: [DecodeDiagnostic("error", "clut.decode_failed", "\(error)")]))
            }
        }
        return palettes
    }

    /// validation.validate_manifest.
    static func validate(_ manifest: GraphicsManifestDocument, strict: Bool,
                         expectedCounts: [(type: String, count: Int)] = expectedOregonColorCounts) -> [DecodeDiagnostic] {
        var diagnostics: [DecodeDiagnostic] = []
        var idsByType: [String: Set<Int>] = [:]
        for image in manifest.images {
            idsByType[image.resource.resourceType, default: []].insert(image.resource.resourceId)
            if image.status == .failed {
                diagnostics.append(DecodeDiagnostic(
                    strict ? "error" : "warning", "validation.failed_image",
                    "\(image.resource.resourceType) \(image.resource.resourceId) failed to decode"))
            }
        }
        for palette in manifest.palettes {
            idsByType[palette.resource.resourceType, default: []].insert(palette.resource.resourceId)
        }
        for (type, expected) in expectedCounts {
            let actual = idsByType[type]?.count ?? 0
            if actual != expected {
                diagnostics.append(DecodeDiagnostic(
                    strict ? "error" : "warning", "validation.count_mismatch",
                    "\(type) count \(actual) did not match expected \(expected)"))
            }
        }
        return diagnostics
    }

    /// exporter.image_output_path: `images/<Type>/<type>_<id>[_<NN>].png`.
    static func imageRelativePath(_ image: DecodedImage) -> String {
        imageRelativePath(type: image.resource.resourceType, id: image.resource.resourceId,
                          frameIndex: image.frameIndex, frameCount: image.frameCount)
    }

    static func imageRelativePath(type: String, id: Int, frameIndex: Int?, frameCount: Int?) -> String {
        var stem = "\(type.lowercased())_\(id)"
        if let frameIndex, let frameCount, frameCount > 1 {
            stem += "_" + (frameIndex < 10 ? "0" : "") + String(frameIndex)
        }
        return "images/\(type)/\(stem).png"
    }

    /// exporter.write_outputs minus contact sheets; the manifest lives at the
    /// output root rather than under `manifests/`.
    static func writeOutputs(_ manifest: inout GraphicsManifestDocument, into output: ExtractionOutput) throws {
        for index in manifest.images.indices {
            guard let image = manifest.images[index].image else { continue }
            let relativePath = imageRelativePath(manifest.images[index])
            try output.writePNG(image, to: relativePath)
            manifest.images[index].imagePath = relativePath
        }
        try output.writeJSON(manifest, to: "graphics_manifest.json")
        try output.writeJSON(GraphicsStatusSummary(manifest), to: "diagnostics/summary.json")
    }
}

// MARK: - Manifest records (models.py)

// Port of scripts/graphics_extract/models.py: the records that make up
// graphics_manifest.json. Encoded field names and null handling match the
// Python `to_dict()` output exactly (nullable fields are emitted as null,
// `palette.resource_id` is omitted when absent).

enum DecodeStatus: String, Encodable {
    case ok
    case partial
    case failed
    var isError: Bool { self == .failed }
}

struct DecodeDiagnostic: Encodable, Equatable {
    let severity: String
    let code: String
    let message: String

    init(_ severity: String, _ code: String, _ message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

struct ResourceInfo: Encodable, Equatable {
    let sourceFile: String
    let resourceType: String
    let resourceId: Int
    let name: String
    let rawLength: Int

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case resourceType = "type"
        case resourceId = "id"
        case name
        case rawLength = "raw_length"
    }
}

struct PaletteInfo: Encodable, Equatable {
    let source: String
    let entryCount: Int
    var resourceId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case source
        case entryCount = "entry_count"
        case resourceId = "resource_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(entryCount, forKey: .entryCount)
        try container.encodeIfPresent(resourceId, forKey: .resourceId)
    }
}

/// One decoded image (or frame) plus its manifest record (models.DecodeImage).
struct DecodedImage: Encodable {
    var resource: ResourceInfo
    var status: DecodeStatus
    var imagePath: String?
    var width: Int?
    var height: Int?
    var mode: String?
    var frameIndex: Int? = nil
    var frameCount: Int? = nil
    var palette: PaletteInfo? = nil
    var byteRanges: [String: [Int]] = [:]
    var diagnostics: [DecodeDiagnostic] = []
    /// Decoded pixels; nil for failed records. Not part of the manifest.
    var image: PNGEncoder.Image? = nil
    /// Original QuickDraw rectangle [top, left, bottom, right].
    var bounds: [Int]? = nil

    enum CodingKeys: String, CodingKey {
        case resource, status, width, height, mode, palette, diagnostics, bounds
        case imagePath = "image_path"
        case frameIndex = "frame_index"
        case frameCount = "frame_count"
        case byteRanges = "byte_ranges"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resource, forKey: .resource)
        try container.encode(status, forKey: .status)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(mode, forKey: .mode)
        try container.encode(frameIndex, forKey: .frameIndex)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(palette, forKey: .palette)
        try container.encode(byteRanges, forKey: .byteRanges)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encodeIfPresent(bounds, forKey: .bounds)
    }

    /// models.DecodeImage with status FAILED and no image (the shape every
    /// decoder returns when it cannot produce pixels).
    static func failed(_ resource: ResourceInfo, width: Int? = nil, height: Int? = nil,
                       diagnostics: [DecodeDiagnostic]) -> DecodedImage {
        DecodedImage(resource: resource, status: .failed, imagePath: nil, width: width, height: height,
                     mode: nil, diagnostics: diagnostics)
    }
}

/// A standalone `clut` resource (models.PaletteRecord).
struct PaletteRecord: Encodable {
    let resource: ResourceInfo
    let palette: PaletteInfo
    let colors: [RGBColor]
    var diagnostics: [DecodeDiagnostic] = []

    enum CodingKeys: String, CodingKey { case resource, palette, colors, diagnostics }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resource, forKey: .resource)
        try container.encode(palette, forKey: .palette)
        try container.encode(colors.map { [Int($0.red), Int($0.green), Int($0.blue)] }, forKey: .colors)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}

/// graphics_manifest.json (models.Manifest).
struct GraphicsManifestDocument: Encodable {
    let sourceFile: String
    var images: [DecodedImage] = []
    var palettes: [PaletteRecord] = []
    var diagnostics: [DecodeDiagnostic] = []

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case images, palettes, diagnostics
    }

    /// Every error-severity diagnostic across the manifest (extract_graphics.error_diagnostics).
    var errorDiagnostics: [DecodeDiagnostic] {
        var errors = diagnostics.filter { $0.severity == "error" }
        for image in images { errors += image.diagnostics.filter { $0.severity == "error" } }
        for palette in palettes { errors += palette.diagnostics.filter { $0.severity == "error" } }
        return errors
    }
}

/// diagnostics/summary.json (exporter.status_summary).
struct GraphicsStatusSummary: Encodable {
    struct Counts: Encodable {
        var ok = 0
        var partial = 0
        var failed = 0
    }
    let sourceFile: String
    let imageCount: Int
    let paletteCount: Int
    let byType: [String: Counts]

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case imageCount = "image_count"
        case paletteCount = "palette_count"
        case byType = "by_type"
    }

    init(_ manifest: GraphicsManifestDocument) {
        sourceFile = manifest.sourceFile
        imageCount = manifest.images.count
        paletteCount = manifest.palettes.count
        var byType: [String: Counts] = [:]
        for image in manifest.images {
            var counts = byType[image.resource.resourceType] ?? Counts()
            switch image.status {
            case .ok: counts.ok += 1
            case .partial: counts.partial += 1
            case .failed: counts.failed += 1
            }
            byType[image.resource.resourceType] = counts
        }
        self.byType = byType
    }
}
