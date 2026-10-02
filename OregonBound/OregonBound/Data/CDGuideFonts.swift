import Foundation

/// Optional original System fonts used by the standalone reader. These bytes
/// come from the player's System file and are independently pinned before use.
struct CDGuideFonts {
    struct Key: Hashable {
        let family: Int
        let size: Int
    }
    struct Selection {
        let key: Key
        let type: String
        let sha256: String
        var relativePath: String { "user-guide/fonts/\(key.family)-\(key.size).\(type.lowercased())" }
    }
    static let selections: [Selection] = [
        Selection(key: .init(family: 3, size: 9), type: "NFNT",
                  sha256: "b2bbba4a4cd1e78320c6a4256bd5d08e01326349804905a1e5d577521f03c754"),
        Selection(key: .init(family: 3, size: 10), type: "NFNT",
                  sha256: "f5a02c0cd63671477151833e5106b0b76187652fd7e7af6fe14fa52c865b5ff9"),
        Selection(key: .init(family: 3, size: 12), type: "NFNT",
                  sha256: "1ae070fb30e3f9912eec605f023db2ca5919624ad898570d8aa12b3e65fec916"),
        Selection(key: .init(family: 3, size: 14), type: "NFNT",
                  sha256: "48b08ab918eb49bbe1796f0a43a8b39323e92bf3e6e8aa666b6e61d0cb921dc2"),
        Selection(key: .init(family: 3, size: 18), type: "NFNT",
                  sha256: "ebc5ae01d0bf7ce62107513f748780a3fcf55c2b4291fa64f57b1bed485be434"),
        Selection(key: .init(family: 21, size: 12), type: "NFNT", sha256: BitmapFontExtractor.cdCreditsSelection.expectedSHA256),
        Selection(key: .init(family: 0, size: 10), type: "sfnt", sha256: CDGuideOutlineFont.expectedSHA256),
    ]
    let resources: [Key: Data]

    init(resources: [Key: Data]) throws {
        guard Set(resources.keys) == Set(Self.selections.map(\.key)) else {
            throw CDGuidePicture.Failure.invalid("incomplete guide font set")
        }
        for selection in Self.selections {
            guard let bytes = resources[selection.key], bytes.count <= 65536,
                  SHA256Hex.digest(bytes) == selection.sha256 else {
                throw CDGuidePicture.Failure.invalid("guide font does not match the verified System file")
            }
        }
        self.resources = resources
    }

    init(systemFork: MacResourceFork) throws {
        func resource(_ type: String, _ id: Int) throws -> MacResource {
            let matches = systemFork.resources.filter { $0.type == type && $0.id == id }
            guard matches.count == 1 else { throw CDGuidePicture.Failure.invalid("missing or duplicate guide System font resource") }
            return matches[0]
        }
        func expanded(_ resource: MacResource) throws -> Data {
            guard resource.data.count <= 65536 else { throw CDGuidePicture.Failure.invalid("excessive System font resource") }
            if resource.isCompressed {
                let reader = ByteSource(resource.data)
                guard try reader.u32(8) <= 65536 else { throw CDGuidePicture.Failure.invalid("excessive expanded System font") }
            }
            return try SystemResourceDecompressor.expand(resource)
        }
        var bytes: [Key: Data] = [:]
        for selection in Self.selections {
            let familyResource = try resource("FOND", selection.key.family)
            let family = try BitmapFontExtractor.parseFOND(expanded(familyResource), resourceID: familyResource.id,
                                                           name: familyResource.name ?? "")
            let size = selection.type == "sfnt" ? 0 : selection.key.size
            let associations = family.associations.filter { $0.size == size && $0.style == 0 }
            guard family.familyID == selection.key.family, associations.count == 1 else {
                throw CDGuidePicture.Failure.invalid("missing or ambiguous guide font association")
            }
            bytes[selection.key] = try expanded(resource(selection.type, associations[0].resourceID))
        }
        try self.init(resources: bytes)
    }

    func write(to output: ExtractionOutput) throws {
        for selection in Self.selections {
            guard let bytes = resources[selection.key] else { throw CDGuidePicture.Failure.invalid("missing guide font") }
            try output.write(bytes, to: selection.relativePath)
        }
    }
    static func load(root: URL) throws -> Self {
        var resources: [Key: Data] = [:]
        for selection in selections {
            let url = try PreparedResourceFile.url(root: root, path: selection.relativePath)
            guard let length = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  length > 0, length <= 65536 else { throw CDGuidePicture.Failure.invalid("prepared guide font length") }
            resources[selection.key] = try Data(contentsOf: url)
        }
        return try Self(resources: resources)
    }

}
