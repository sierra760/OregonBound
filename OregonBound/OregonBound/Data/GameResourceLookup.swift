import Foundation

/// Effective resource lookup without discarding the full source catalog.
/// Companions are opened after the application. Supported companions have
/// disjoint identities, so their filesystem enumeration order is immaterial.
struct GameResourceLookup {
    struct Index: Codable {
        let schemaVersion: Int
        let edition: GameEdition
        let entries: [GameResourceCatalog.Entry]
    }
    enum Depth: Int { case monochrome = 1, color16 = 4, color256 = 8 }
    enum Failure: Error, CustomStringConvertible {
        case foreignSource(GameDataSourceRole, GameEdition)
        case ambiguous(String, Int, [GameDataSourceRole])
        case unsupportedCDSelector

        var description: String {
            switch self {
            case .foreignSource(let role, let edition):
                return "\(role.title) does not belong to \(edition.rawValue)."
            case .ambiguous(let type, let id, let roles):
                return "Ambiguous resource \(type) \(id) in \(roles.map(\.title).joined(separator: ", "))."
            case .unsupportedCDSelector:
                return "The CD graphics selector requires Macintosh CD 1.2 data."
            }
        }
    }

    private typealias Identity = GameDataSourceCatalog.ResourceIdentity
    let index: Index
    private let selected: [Identity: GameResourceCatalog.Entry]

    init(catalog: GameResourceCatalog) throws {
        try self.init(edition: catalog.edition, entries: catalog.entries)
    }

    init(edition: GameEdition, entries: [GameResourceCatalog.Entry]) throws {
        let application: GameDataSourceRole = edition == .macintosh11 ? .classicApplication : .cdApplication
        var groups: [Identity: [GameResourceCatalog.Entry]] = [:]
        for entry in entries {
            guard entry.role == .system || entry.role.edition == edition else {
                throw Failure.foreignSource(entry.role, edition)
            }
            groups[Identity(type: entry.type, id: entry.id), default: []].append(entry)
        }
        var selected: [Identity: GameResourceCatalog.Entry] = [:]
        for (identity, candidates) in groups {
            // Reject duplicates even when a higher-priority source would hide them.
            guard Set(candidates.map(\.role)).count == candidates.count else {
                throw Failure.ambiguous(identity.type, identity.id, candidates.map(\.role))
            }
            let companions = candidates.filter { $0.role != application && $0.role != .system }
            guard companions.count <= 1 else {
                throw Failure.ambiguous(identity.type, identity.id, companions.map(\.role))
            }
            selected[identity] = companions.first ?? candidates.first { $0.role == application }
                ?? candidates.first { $0.role == .system }
        }
        self.selected = selected
        index = Index(schemaVersion: 1, edition: edition, entries: selected.values.sorted {
            ($0.type, $0.id) < ($1.type, $1.id)
        })
    }

    func resource(type: String, id: Int) -> GameResourceCatalog.Entry? {
        selected[Identity(type: type, id: id)]
    }

    /// The CD display object chooses between caller-supplied IDs by its depth;
    /// the global display depth independently chooses Imag versus Ima4. Neither
    /// a missing variant nor an explicit empty placeholder triggers fallback.
    func cdImage(monochromeID: Int, colorID: Int, imageDepth: Depth,
                 displayDepth: Depth) throws -> GameResourceCatalog.Entry? {
        guard index.edition == .macintoshCD12 else { throw Failure.unsupportedCDSelector }
        return resource(type: displayDepth == .color16 ? "Ima4" : "Imag",
                        id: imageDepth == .monochrome ? monochromeID : colorID)
    }
}
