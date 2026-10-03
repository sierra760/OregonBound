import Foundation

/// Edition-scoped audio boundary for prepared imports. Resource lookup chooses
/// the source before any file is read; missing data never falls back by ID.
struct PreparedSoundLibrary {
    enum Failure: Error, CustomStringConvertible {
        case invalidSources
        case invalidManifest(GameDataSourceRole)
        case invalidSound(GameDataSourceRole, Int)
        var description: String {
            switch self {
            case .invalidSources: return "The prepared sound sources do not match this edition."
            case .invalidManifest(let role): return "Invalid sound manifest for \(role.title). Re-import the game data."
            case .invalidSound(let role, let id): return "Invalid sound \(id) in \(role.title). Re-import the game data."
            }
        }
    }
    private struct LocatedSound {
        let role: GameDataSourceRole
        let record: SoundExtractor.Record
        let path: String
    }
    private let root: URL
    private let sounds: [Int: LocatedSound]
    let edition: GameEdition

    init(root: URL, lookup: GameResourceLookup, soundSources: [GameDataSourceRole]) throws {
        let included = Set(soundSources)
        guard included.count == soundSources.count,
              included.isSubset(of: Set(lookup.index.edition.requiredRoles)) else { throw Failure.invalidSources }
        // Filter after effective lookup, so excluding a source never exposes a
        // lower-priority resource with the same ID. System audio is not prepared.
        let entries = lookup.index.entries.filter { $0.type == "snd " && included.contains($0.role) }
        var selected: [Int: LocatedSound] = [:]
        for role in Set(entries.map(\.role)) {
            let prefix = "sources/\(role.rawValue)/"
            let data = try Data(contentsOf: PreparedResourceFile.url(root: root, path: prefix + "sounds/manifest.json"))
            let manifest = try JSONDecoder().decode(SoundExtractor.Manifest.self, from: data)
            guard manifest.schemaVersion == 1,
                  Set(manifest.sounds.map(\.id)).count == manifest.sounds.count,
                  manifest.sounds.allSatisfy({
                      (-32768...32767).contains($0.id) && $0.sampleCount > 0 && $0.fixedSampleRate >= 32769 &&
                      $0.path == "sounds/snd_\($0.id).wav"
                  }) else { throw Failure.invalidManifest(role) }
            let records = Dictionary(uniqueKeysWithValues: manifest.sounds.map { ($0.id, $0) })
            for entry in entries where entry.role == role {
                guard let record = records[entry.id] else { throw Failure.invalidManifest(role) }
                selected[entry.id] = LocatedSound(role: role, record: record, path: prefix + record.path)
            }
        }
        self.root = root
        sounds = selected
        edition = lookup.index.edition
    }

    func sample(_ id: Int) throws -> OriginalSoundSample? {
        guard let sound = sounds[id] else { return nil }
        let wav = try Data(contentsOf: PreparedResourceFile.url(root: root, path: sound.path))
        guard let sample = OriginalSoundSample(record: sound.record, wav: wav) else {
            throw Failure.invalidSound(sound.role, id)
        }
        return sample
    }
}
