import Foundation

/// Source-qualified inventory. Equal numeric IDs in Imag and Ima4, or in
/// different files, remain distinct. Presentation chooses among them later.
struct GameResourceCatalog: Codable {
    struct Source: Codable {
        let role: GameDataSourceRole
        let origin: String
        let sha256: String
        let length: Int
    }
    enum Disposition: String, Codable {
        case resource
        case emptyPlaceholder
    }
    struct Entry: Codable, Equatable {
        let role: GameDataSourceRole
        let type: String
        let id: Int
        let name: String?
        let attributes: UInt8
        let length: Int
        let sha256: String
        let disposition: Disposition
    }
    enum Failure: Error, CustomStringConvertible {
        case unexpectedEmpty(GameDataSourceRole, String, Int)
        var description: String {
            switch self {
            case .unexpectedEmpty(let role, let type, let id):
                return "Unexpected empty graphics resource \(type) \(id) in \(role.title)."
            }
        }
    }

    let edition: GameEdition
    let sources: [Source]
    let entries: [Entry]

    init(selection: GameDataSourceCatalog.Selection) throws {
        edition = selection.edition
        var sources: [Source] = []
        var entries: [Entry] = []
        for role in GameDataSourceRole.allCases {
            guard let candidate = selection.sources[role] else { continue }
            sources.append(Source(role: role, origin: candidate.source.origin, sha256: candidate.sha256,
                                  length: candidate.source.resourceFork.count))
            for resource in candidate.fork.resources.sorted(by: { ($0.type, $0.id) < ($1.type, $1.id) }) {
                var disposition = Disposition.resource
                if ["Imag", "Ima4"].contains(resource.type), resource.data.count >= 2,
                   resource.data.prefix(2).allSatisfy({ $0 == 0 }) {
                    guard resource.data.count == 2,
                          Self.isKnownPlaceholder(edition: edition, role: role, type: resource.type, id: resource.id) else {
                        throw Failure.unexpectedEmpty(role, resource.type, resource.id)
                    }
                    disposition = .emptyPlaceholder
                }
                entries.append(Entry(role: role, type: resource.type, id: resource.id, name: resource.name,
                                     attributes: resource.attributes, length: resource.data.count,
                                     sha256: GameDataSourceCatalog.Candidate.digest(resource.data), disposition: disposition))
            }
        }
        self.sources = sources
        self.entries = entries
    }

    /// Six declared-empty records in the CD 1.2 inventory. This is metadata,
    /// not a fabricated image; any other zero-frame graphics record is invalid.
    static func isKnownPlaceholder(edition: GameEdition, role: GameDataSourceRole, type: String, id: Int) -> Bool {
        guard edition == .macintoshCD12 else { return false }
        switch (role, type) {
        case (.graphics1, "Imag"), (.graphics3, "Ima4"): return [15522, 15523].contains(id)
        case (.graphics2, "Imag"): return [5522, 5523].contains(id)
        default: return false
        }
    }
}
