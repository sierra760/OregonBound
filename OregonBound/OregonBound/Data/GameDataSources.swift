import Foundation
import CryptoKit

/// Stable identities for the two Macintosh releases supported by the source catalog.
enum GameEdition: String, Codable, CaseIterable {
    case macintosh11 = "macintosh-1.1"
    case macintoshCD12 = "macintosh-cd-1.2"

    var title: String {
        self == .macintosh11 ? "The Oregon Trail (Macintosh 1.1)" : "Oregon Trail CD (Macintosh 1.2)"
    }

    var requiredRoles: [GameDataSourceRole] {
        switch self {
        case .macintosh11: return [.classicApplication, .classicGraphics]
        case .macintoshCD12:
            return [.cdApplication, .graphics1, .graphics2, .graphics3, .graphics4,
                    .guide1, .guide2, .guide3, .sound1, .sound2, .sound3, .sound4, .sound5]
        }
    }
}

enum GameDataSourceRole: String, Codable, CaseIterable {
    case classicApplication, classicGraphics, cdApplication
    case graphics1, graphics2, graphics3, graphics4
    case guide1, guide2, guide3, sound1, sound2, sound3, sound4, sound5
    case system, cdUserGuide

    var title: String {
        switch self {
        case .classicApplication: return "Oregon Trail 1.1 application"
        case .classicGraphics: return "Oregon Color"
        case .cdApplication: return "Oregon Trail CD 1.2 application"
        case .graphics1: return "Graphics 1"
        case .graphics2: return "Graphics 2"
        case .graphics3: return "Graphics 3"
        case .graphics4: return "Graphics 4"
        case .guide1: return "Guide Book 1"
        case .guide2: return "Guide Book 2"
        case .guide3: return "Guide Book 3"
        case .sound1: return "Oregon Sound 1"
        case .sound2: return "Oregon Sound 2"
        case .sound3: return "Oregon Sound 3"
        case .sound4: return "Oregon Sound 4"
        case .sound5: return "Oregon Sound 5"
        case .system: return "System"
        case .cdUserGuide: return "On-line User’s Guide"
        }
    }

    var edition: GameEdition? {
        switch self {
        case .classicApplication, .classicGraphics: return .macintosh11
        case .system: return nil
        default: return .macintoshCD12
        }
    }
}

/// Content-based source discovery. This catalog does not choose rendering
/// precedence and does not activate an edition or replace an installed import.
enum GameDataSourceCatalog {
    struct Candidate {
        let source: MacForkSource
        let fork: MacResourceFork
        let sha256: String

        init(source: MacForkSource, fork: MacResourceFork) {
            self.source = source
            self.fork = fork
            self.sha256 = Self.digest(source.resourceFork)
        }

        static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Selection {
        let edition: GameEdition
        let sources: [GameDataSourceRole: Candidate]
        let unrecognized: [Candidate]
    }

    enum Failure: Error, CustomStringConvertible {
        case noEdition
        case mixedEditions
        case missing([GameDataSourceRole])
        case ambiguous(GameDataSourceRole, [String])
        case conflictingRoles(String)
        case duplicateResource(String, String, Int)

        var description: String {
            switch self {
            case .noEdition:
                return "No supported Oregon Trail edition was identified. Supply Macintosh 1.1 or Macintosh CD 1.2 files."
            case .mixedEditions:
                return "Files from both Macintosh 1.1 and CD 1.2 were supplied. Import one edition at a time."
            case .missing(let roles):
                return "Still missing: " + roles.map(\.title).joined(separator: ", ") + "."
            case .ambiguous(let role, let origins):
                return "Conflicting copies of \(role.title): \(origins.joined(separator: ", ")). Supply one consistent copy."
            case .conflictingRoles(let origin):
                return "The resource contents in \(origin) match more than one source role."
            case .duplicateResource(let origin, let type, let id):
                return "Duplicate resource \(type) \(id) in \(origin)."
            }
        }
    }

    static func read(_ urls: [URL], progress: (String) -> Void) throws -> [Candidate] {
        var candidates: [Candidate] = []
        for url in urls {
            progress("Reading \(url.lastPathComponent)…")
            for source in try MacContainers.forkSources(at: url) {
                guard let fork = try? MacResourceFork(data: source.resourceFork), !fork.resources.isEmpty else { continue }
                candidates.append(Candidate(source: source, fork: fork))
            }
        }
        return candidates
    }

    static func select(_ candidates: [Candidate]) throws -> Selection {
        var groups: [GameDataSourceRole: [Candidate]] = [:]
        var unknown: [Candidate] = []
        var editions: Set<GameEdition> = []
        for candidate in candidates {
            let roles = identify(candidate.fork)
            guard roles.count <= 1 else { throw Failure.conflictingRoles(candidate.source.origin) }
            guard let role = roles.first else { unknown.append(candidate); continue }
            var identities: Set<ResourceIdentity> = []
            for resource in candidate.fork.resources {
                guard identities.insert(.init(type: resource.type, id: resource.id)).inserted else {
                    throw Failure.duplicateResource(candidate.source.origin, resource.type, resource.id)
                }
            }
            if let edition = role.edition { editions.insert(edition) }
            if !(groups[role] ?? []).contains(where: { $0.sha256 == candidate.sha256 }) {
                groups[role, default: []].append(candidate)
            }
        }
        guard editions.count <= 1 else { throw Failure.mixedEditions }
        guard let edition = editions.first else { throw Failure.noEdition }
        var selected: [GameDataSourceRole: Candidate] = [:]
        for role in GameDataSourceRole.allCases {
            guard let matching = groups[role] else { continue }
            guard matching.count == 1 else {
                throw Failure.ambiguous(role, matching.map { $0.source.origin }.sorted())
            }
            selected[role] = matching[0]
        }
        let missing = edition.requiredRoles.filter { selected[$0] == nil }
        guard missing.isEmpty else { throw Failure.missing(missing) }
        return Selection(edition: edition, sources: selected, unrecognized: unknown)
    }

    struct ResourceIdentity: Hashable {
        let type: String
        let id: Int
    }

    /// Markers and resource IDs from the supported 1.1 and CD 1.2 inventories.
    /// Recognition is separate from payload decoding/complete-resource validation.
    static func identify(_ fork: MacResourceFork) -> [GameDataSourceRole] {
        var roles: [GameDataSourceRole] = []
        func version(_ major: UInt8, _ minor: UInt8) -> Bool {
            guard let data = fork["vers", 1]?.data else { return false }
            return Array(data.prefix(2)) == [major, minor]
        }
        let appFamilies = ["DITL", "STR#", "WST#", "NFNT", "HVof"].allSatisfy(fork.contains)
        if appFamilies && fork["ORGN", 0] != nil && fork.contains("snd ") && version(1, 0x10) {
            roles.append(.classicApplication)
        }
        if appFamilies && fork["OTCD", 0] != nil && version(1, 0x20) { roles.append(.cdApplication) }
        if fork["Imag", 10128] != nil && fork.contains("cicn") && fork.contains("clut")
            && !fork.contains("OTSG") && version(1, 0x10) { roles.append(.classicGraphics) }
        if fork["OTSG", 128] != nil && fork["Imag", 10128] != nil && fork.contains("cicn") { roles.append(.graphics1) }
        if fork["OTSG", 133] != nil && fork["Imag", 128] != nil && fork.contains("TERR") && fork.contains("clut") {
            roles.append(.graphics2)
        }
        if fork["Ima4", 10128] != nil && fork["Ima4", 20300] != nil { roles.append(.graphics3) }
        let ima4IDs = Set(fork.resources(ofType: "Ima4").map(\.id))
        if ima4IDs == Set(20200...20262) { roles.append(.graphics4) }
        let soundIDs = Set(fork.resources(ofType: "snd ").map(\.id))
        for (role, expected) in soundGroups where soundIDs == expected { roles.append(role) }
        if fork["Hypp", 0] != nil && fork["PMAP", 128] != nil && fork["SCNM", 128] != nil
            && fork["STR#", 128] != nil && fork["PICT", 4000] != nil && version(1, 0x10) {
            roles.append(.cdUserGuide)
        }
        if fork["CDEF", 1] != nil && fork["FOND", 0] != nil && fork["FOND", 3] != nil && fork["ICON", 0] != nil {
            roles.append(.system)
        }
        return roles
    }

    private static let soundGroups: [(GameDataSourceRole, Set<Int>)] = {
        var groups: [(GameDataSourceRole, Set<Int>)] = []
        groups.append((.guide1, Set(6001...6024)))
        groups.append((.guide2, Set(6025...6049)))
        groups.append((.guide3, Set(6050...6073)))
        func conversations(_ range: ClosedRange<Int>) -> Set<Int> {
            Set(range.flatMap { number -> [Int] in [number * 10 + 1, number * 10 + 2, number * 10 + 3] })
        }
        groups.append((.sound1, conversations(310...318)))
        groups.append((.sound2, conversations(319...327)))
        groups.append((.sound3, Set(1000...1005).union([2000])))
        groups.append((.sound4, Set(1006...1017)))
        let effects = Set(4000...4015).union([4020]).union(9001...9008).union(10000...10003)
        groups.append((.sound5, effects))
        return groups
    }()
}
