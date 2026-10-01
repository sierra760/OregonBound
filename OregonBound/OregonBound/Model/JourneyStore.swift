import Foundation

struct SavedJourney: Codable {
    let format: String
    let version: Int
    let journey: Journey
    var edition: GameEdition? = nil
}

struct HighScore: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let profession: Profession
    let difficulty: Difficulty
    let score: Int
    let date: Date
}

struct JourneyStore {
    let directory: URL
    let edition: GameEdition
    private let defaultPreferences: OriginalPreferences.Configuration?
    init(directory: URL? = nil, edition: GameEdition = GameData.edition,
         defaultPreferences: OriginalPreferences.Configuration? = nil,
         session: PreparedGameSession? = GameData.preparedSession) {
        self.edition = edition
        let preparedDefaults = session.flatMap { $0.edition == edition ? OriginalPreferences.Configuration(defaults: $0.preferenceDefaults) : nil }
        self.defaultPreferences = defaultPreferences ?? preparedDefaults ?? (edition == .macintosh11 ? .init() : nil)

        if let directory { self.directory = Self.directory(for: edition, base: directory); return }
        #if DEBUG
        // UI fidelity fixtures must never replace a player's persistent save.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-save-directory"),
           arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") {
            self.directory = Self.directory(for: edition, base: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
            return
        }
        #endif
        self.directory = Self.directory(for: edition, base: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OregonBound", isDirectory: true))
    }
    /// Classic retains its historical location; no player files are moved.
    /// An injected directory is the shared base, not a namespace override.
    private static func directory(for edition: GameEdition, base: URL) -> URL {
        edition == .macintosh11 ? base : base.appendingPathComponent("editions/\(edition.rawValue)", isDirectory: true)
    }

    private struct PreferencesArchive: Codable {
        let format: String
        let version: Int
        let edition: GameEdition
        let configuration: OriginalPreferences.Configuration
    }
    private func initialPreferences() throws -> OriginalPreferences.Configuration {
        guard let defaultPreferences else { throw GameRuleError("The preference defaults for this edition have not been loaded.") }
        return defaultPreferences
    }

    var saveURL: URL { directory.appendingPathComponent("journey.json") }
    var hasSave: Bool { FileManager.default.fileExists(atPath: saveURL.path) }
    private var scoresURL: URL { directory.appendingPathComponent("hall-of-fame.json") }

    private var preferencesURL: URL { directory.appendingPathComponent("preferences.json") }
    func preferences() throws -> OriginalPreferences.Configuration {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return try initialPreferences() }
        let data = try limitedData(preferencesURL)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if object?["format"] != nil || object?["edition"] != nil || object?["version"] != nil {
            let archive: PreferencesArchive
            do { archive = try JSONDecoder().decode(PreferencesArchive.self, from: data) }
            catch { throw GameRuleError("The saved preferences use an unsupported format or edition.") }
            guard archive.format == "OregonBoundPreferences", archive.version == 1, archive.edition == edition else {
                throw GameRuleError("The saved preferences belong to another edition or use an unsupported format.")
            }
            return archive.configuration
        }
        guard edition == .macintosh11 else { throw GameRuleError("Preferences without edition information belong to Macintosh 1.1.") }
        if let legacy = try? JSONDecoder().decode(OriginalPreferences.Configuration.self, from: data) { return legacy }
        return try initialPreferences()
    }
    func savePreferences(_ configuration: OriginalPreferences.Configuration) throws {
        try write(PreferencesArchive(format: "OregonBoundPreferences", version: 1, edition: edition,
                                     configuration: configuration), to: preferencesURL)
    }

    func save(_ journey: Journey, to destination: URL? = nil) throws {
        try validate(journey)
        guard journey.canSave else { throw GameRuleError("Finish the hunt or river run before saving.") }
        try write(SavedJourney(format: "OregonBound", version: 2, journey: journey, edition: edition), to: destination ?? saveURL)
    }

    func load(from source: URL? = nil) throws -> Journey {
        do {
            let saved = try JSONDecoder().decode(SavedJourney.self, from: limitedData(source ?? saveURL))
            guard saved.format == "OregonBound" else { throw GameRuleError("This saved game uses an unsupported format.") }
            let savedEdition: GameEdition
            switch saved.version {
            case 1 where saved.edition == nil: savedEdition = .macintosh11
            case 2:
                guard let explicit = saved.edition else { throw GameRuleError("This saved game is missing its edition.") }
                savedEdition = explicit
            default: throw GameRuleError("This saved game uses an unsupported format.")
            }
            guard savedEdition == edition, saved.journey.gameEdition == savedEdition else {
                throw GameRuleError("This saved game belongs to a different Oregon Trail edition.")
            }
            var journey = saved.journey
            journey.edition = savedEdition
            // Validate the arithmetic migration inputs before multiplying them.
            guard journey.inventory.valid,
                  journey.inventoryUnitsVersion != nil || journey.inventory[.oxen] <= 40 else {
                throw GameRuleError("The saved game contains invalid inventory data.")
            }
            journey.ensureOriginalState()
            // Earlier CD saves used seven slots; their completed outcome did not
            // lose perishables. Preserve those losses without drawing again.
            if savedEdition == .macintoshCD12 && journey.originalRiverOutcome?.losses.count == 7 {
                journey.originalRiverOutcome?.losses.append(0)
            }
            try validate(journey)
            guard journey.canSave else { throw GameRuleError("This save was interrupted during a minigame.") }
            return journey
        } catch let error as GameRuleError { throw error }
        catch { throw GameRuleError("The saved game could not be read. \(error.localizedDescription)") }
    }

    /// Version2 stores the actual table: an empty table must not regenerate the
    /// authored defaults. Legacy arrays are migrated by merging their players.
    private struct LegendsArchive: Codable {
        let format: String
        let version: Int
        var players: [HighScore]
        var legends: [OriginalEndingPresentation.Legend]
        var edition: GameEdition? = nil
    }

    private func scoreArchive() throws -> LegendsArchive {
        guard FileManager.default.fileExists(atPath: scoresURL.path) else {
            return .init(format: "OregonBoundLegends", version: 3, players: [],
                         legends: OriginalEndingPresentation.initialLegends, edition: edition)
        }
        let data = try limitedData(scoresURL)
        let archive: LegendsArchive
        if let old = try? JSONDecoder().decode([HighScore].self, from: data) {
            guard edition == .macintosh11 else { throw GameRuleError("A legacy score table belongs to Macintosh 1.1.") }
            let players = old.enumerated().sorted {
                $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score
            }.map(\.element)
            archive = .init(format: "OregonBoundLegends", version: 2, players: players,
                            legends: OriginalEndingPresentation.legends(with: players))
        } else {
            archive = try JSONDecoder().decode(LegendsArchive.self, from: data)
        }
        let legacyClassic = archive.version == 2 && archive.edition == nil && edition == .macintosh11
        guard archive.format == "OregonBoundLegends",
              legacyClassic || (archive.version == 3 && archive.edition == edition),
              archive.players.count <= 10, archive.legends.count <= 10,
              Set(archive.players.map(\.id)).count == archive.players.count,
              Set(archive.legends.map(\.id)).count == archive.legends.count,
              archive.players.allSatisfy({ (0...Int(Int32.max)).contains($0.score) && !$0.name.isEmpty && $0.name.count <= 256 }),
              archive.legends.allSatisfy({ (1...Int(Int32.max)).contains($0.score) && !$0.name.isEmpty && $0.name.count <= 256 && !$0.id.isEmpty }),
              zip(archive.legends, archive.legends.dropFirst()).allSatisfy({ $0.score >= $1.score }) else {
            throw GameRuleError("The saved List of Legends is invalid.")
        }
        return .init(format: "OregonBoundLegends", version: 3, players: archive.players,
                     legends: archive.legends, edition: edition)
    }

    /// Compatibility metadata API. Original presentation must use legends().
    func scores() throws -> [HighScore] { try scoreArchive().players }

    func legends(excluding id: UUID? = nil) throws -> [OriginalEndingPresentation.Legend] {
        try scoreArchive().legends.filter { $0.id != id?.uuidString }
    }

    /// CODE15:0828–0860 applies queued removals by exact name and score on Done.
    /// IDs are port metadata, so a restored original row can still match a
    /// removal queued before the user pressed Original.
    func removeLegends(_ removed: [OriginalEndingPresentation.Legend]) throws {
        guard !removed.isEmpty else { return }
        var archive = try scoreArchive()
        for entry in removed {
            if let index = archive.legends.firstIndex(where: { $0.name == entry.name && $0.score == entry.score }) {
                let removedID = archive.legends.remove(at: index).id
                archive.players.removeAll { $0.id.uuidString == removedID }
            }
        }
        try write(archive, to: scoresURL)
    }

    /// Original+Yes restores the authored table immediately, rather than making
    /// it empty. Done has separate pending removals in the editor session.
    func restoreOriginalLegends() throws {
        try write(LegendsArchive(format: "OregonBoundLegends", version: 3, players: [],
                                 legends: OriginalEndingPresentation.initialLegends, edition: edition), to: scoresURL)
    }

    func recordScore(_ trip: Journey, name: String? = nil) throws {
        guard trip.gameEdition == edition else { throw GameRuleError("The journey belongs to a different Oregon Trail edition.") }
        guard trip.phase == .finished, trip.won else { return }
        var archive = try scoreArchive()
        guard !archive.players.contains(where: { $0.id == trip.id }),
              !archive.legends.contains(where: { $0.id == trip.id.uuidString }) else { return }
        let score = JourneyEngine.score(trip)
        let enteredName = name ?? trip.members.first?.name ?? "Traveler"
        guard !enteredName.isEmpty, enteredName.count <= 256,
              (0...Int(Int32.max)).contains(score) else {
            throw GameRuleError("The List of Legends entry is invalid.")
        }
        guard let index = OriginalEndingPresentation.insertionIndex(score: score, legends: archive.legends) else { return }
        archive.legends.insert(.init(id: trip.id.uuidString, name: enteredName, score: score), at: index)
        archive.legends = Array(archive.legends.prefix(10))
        archive.players.append(HighScore(id: trip.id, name: enteredName, profession: trip.profession,
                                         difficulty: trip.difficulty, score: score, date: Date()))
        archive.players = Array(archive.players.enumerated().sorted {
            $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score
        }.prefix(10).map(\.element))
        try write(archive, to: scoresURL)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func limitedData(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 2_000_000 else { throw GameRuleError("This saved file is too large to be a valid game.") }
        return try Data(contentsOf: url)
    }

    func validate(_ trip: Journey) throws {
        guard trip.gameEdition == edition else { throw GameRuleError("The journey belongs to a different Oregon Trail edition.") }
        guard trip.inventoryUnitsVersion == nil || trip.inventoryUnitsVersion == 1,
              TrailCatalog.contains(trip.locationID), trip.destinationID.map(TrailCatalog.contains) ?? true,
              (1...5).contains(trip.members.count), Set(trip.members.map(\.id)).count == trip.members.count,
              trip.members.allSatisfy({ $0.health.isFinite && (0...100).contains($0.health) && (0...255).contains($0.sickDays) && !$0.name.isEmpty && $0.name.count <= 24 }),
              (3...8).contains(trip.departureMonth), (0...(65_536 * 366)).contains(trip.daysElapsed),
              ((trip.originalCashOverdraft == true ? -990_000 : 0)...1_000_000).contains(trip.cash), trip.inventory.valid,
              trip.gameEdition == .macintoshCD12 || trip.inventory.perishableFood == 0,
              trip.legacyOxenLimit.map({ (40...80).contains($0) }) ?? true,
              trip.inventory[.oxen] <= (trip.legacyOxenLimit ?? Supply.oxen.capacity),
              (0...4000).contains(trip.miles), (0...500).contains(trip.legDistance), (0...trip.legDistance).contains(trip.legProgress),
              trip.riverDepth.isFinite, (0...(trip.originalRiverDimensions == nil ? 50 : 127.5)).contains(trip.riverDepth),
              (0...2550).contains(trip.riverWidth), (0...255).contains(trip.delayDays),
              trip.visited.allSatisfy(TrailCatalog.contains), Set(trip.visited).count == trip.visited.count,
              trip.journal.count <= 500, Set(trip.journal.map(\.id)).count == trip.journal.count,
              trip.journal.allSatisfy({ (0...1_000_000).contains($0.id) && (0...trip.daysElapsed).contains($0.day) && $0.text.count < 5000 }),
              trip.brokenPart.map({ [.wheels, .axles, .tongues].contains($0) }) ?? true,
              trip.additionalBrokenParts.map({ $0.count <= 2 && Set($0).count == $0.count && $0.allSatisfy { [.wheels, .axles, .tongues].contains($0) } }) ?? true,
              trip.additionalBrokenParts?.isEmpty != false || trip.brokenPart != nil,
              trip.originalCashOverdraft != true || trip.original != nil,
              !trip.won || trip.phase == .finished,
              trip.phase == .finished || !trip.livingMembers.isEmpty else { throw GameRuleError("The saved game contains invalid journey data.") }
        if let dimensions = trip.originalRiverDimensions {
            guard trip.riverDepth == dimensions.depthFeet,
                  trip.riverWidth == dimensions.widthFeet else {
                throw GameRuleError("The saved river dimensions are inconsistent.")
            }
        }
        if let outcome = trip.originalRiverOutcome {
            guard trip.phase == .river, (1...4).contains(outcome.requestedMethodRaw), (1...3).contains(outcome.animationMethodRaw),
                  (0...2).contains(outcome.failureKind), (0...4).contains(outcome.status),
                  (-328...983).contains(outcome.currentFactor), outcome.losses.count == Inventory.itemCount(for: trip.gameEdition),
                  outcome.losses.enumerated().allSatisfy({ index, loss in
                      let limit = index == 0 ? 80 : index == 7 ? Inventory.perishableFoodCapacity : Supply.allCases[index].capacity
                      return (0...limit).contains(loss)
                  }), Set(outcome.drownedMembers).count == outcome.drownedMembers.count,
                  outcome.drownedMembers.allSatisfy(trip.members.indices.contains),
                  outcome.presentationRandomTicks.map({ (0..<180).contains($0) }) ?? true else {
                throw GameRuleError("The saved river outcome is invalid.")
            }
            if outcome.phase == .animation {
                guard outcome.losses.allSatisfy({ $0 == 0 }), outcome.drownedMembers.isEmpty,
                      outcome.presentationRandomTicks == nil else {
                    throw GameRuleError("The saved river animation contains unprepared losses.")
                }
            } else if outcome.phase == .result && [1, 2].contains(outcome.status) {
                guard outcome.presentationRandomTicks != nil else {
                    throw GameRuleError("The saved river result is missing its presentation delay.")
                }
            }
        }
        if let state = trip.original {
            guard state.badness <= 139, state.flags & 0xf1 == 0,
                  state.cdWagonWeight.map({ trip.gameEdition == .macintoshCD12 && (0...4328).contains($0) }) ?? true,
                  state.weather.region < 6, state.weather.temperature <= 5,
                  (state.weather.category & 127) <= (trip.gameEdition == .macintoshCD12 ? 10 : 9) else {
                throw GameRuleError("The saved game contains invalid original simulation state.")
            }
        }
        if let session = trip.originalTradeSession {
            guard session.isValid(in: trip.gameEdition), [.travel, .landmark, .river, .fork].contains(trip.phase),
                  trip.originalRiverOutcome == nil else {
                throw GameRuleError("The saved trade offer is invalid.")
            }
        }
        if trip.phase == .travel && !trip.location.routes.contains(where: { $0.destination == trip.destinationID && $0.miles == trip.legDistance }) {
            throw GameRuleError("The saved journey has an invalid route.")
        }
        if trip.phase == .river && !trip.location.river { throw GameRuleError("The saved crossing is not at a river.") }
        if trip.phase == .fork && trip.locationID != "dalles" && trip.location.routes.count < 2 {
            throw GameRuleError("The saved journey has an invalid trail fork.")
        }
    }
}
