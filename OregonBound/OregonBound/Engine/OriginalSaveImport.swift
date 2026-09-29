import Foundation

/// A read-only, restricted Journey projection, not a lossless Journey conversion.
/// The result always retains the entire original archive and compact journal.
/// See ORIGINAL_SAVE_IMPORT.md for supported states and original load semantics.
enum OriginalSaveImport {
    struct RuntimeContext {
        /// Native metadata has no original saved-file equivalent.
        let journeyID: UUID
        let difficulty: Difficulty
        /// CODE6 saves neither QuickDraw randSeed nor A5−2392 hunt mileage.
        let randomSeed: UInt32
        let lastSuccessfulHuntMileage: Int
    }
    enum ImportError: Error, Equatable {
        case unsupported(field: String, value: Int)
        case inconsistent(field: String)
        case invalidName(memberSlot: Int)
    }
    enum JournalState: Equatable {
        case decoded(OriginalSaveJournal)
        case invalidUsedRange
        case undecodable(OriginalSaveJournal.DecodeError)
    }
    struct Result {
        let archive: OriginalSaveArchive
        let journey: Journey
        let compactJournal: JournalState
        /// Details retained in the archive but not mapped to native JournalEntry rows.
        let unmapped = ["Original journal visibility, row layout and complete event text",
                       "Opaque archive fields, inactive wagon records and journal bookkeeping",
                       "Native identity/difficulty and unsaved application globals require caller context"]
    }

    static func read(_ archive: OriginalSaveArchive, runtime: RuntimeContext) throws -> Result {
        func require(_ value: Int, _ range: ClosedRange<Int>, _ field: String) throws {
            guard range.contains(value) else { throw ImportError.unsupported(field: field, value: value) }
        }
        let player = try archive.singleWagonPlayerIndex()
        try require(player, 0...0, "noncanonical player mapping")
        let world = Array(archive.worldBytes)
        try require(Int(world[8]), 1...1, "current wagon count")
        try require(Int(world[0x23f]), 1...1, "active wagon count")
        let destination = archive.destinationIndex
        try require(destination, -1...16, "invalid destination")
        let remaining = Int(archive.worldByte(.remainingMiles))
        if destination == 16 && remaining == 0 {
            throw ImportError.unsupported(field: "completed overland ending", value: destination)
        }
        let routeFlags = Int(archive.worldByte(.routeFlags))
        try require(routeFlags, 0...3, "rafting or unsupported route flags")
        try require(runtime.lastSuccessfulHuntMileage, 0...65535, "runtime hunt mileage")

        let departureMonth = Int(archive.worldByte(.departureMonth))
        try require(departureMonth, 3...8, "departure month")
        try require(Int(archive.worldByte(.departureDay)), 1...1, "departure day")
        let year = Int(archive.worldWord(.year)), month = Int(archive.worldByte(.month)), day = Int(archive.worldByte(.day))
        let elapsed = try elapsedDays(year: year, month: month, day: day, departureMonth: departureMonth)
        let pace = Int(archive.worldByte(.pace))
        try require(pace, 0...2, "pace")
        let rations = Int(try archive.playerByte(.rations, record: player))
        try require(rations, 0...2, "rations")
        let occupation = Int(try archive.playerByte(.occupation, record: player))
        try require(occupation, 0...7, "occupation")
        guard let speed = OriginalPreferences.Speed(rawValue: archive.worldByte(.simulationSpeed)) else {
            throw ImportError.unsupported(field: "simulation speed", value: Int(archive.worldByte(.simulationSpeed)))
        }
        guard let huntTime = OriginalPreferences.HuntTime(rawValue: archive.worldByte(.huntTime)) else {
            throw ImportError.unsupported(field: "hunting time", value: Int(archive.worldByte(.huntTime)))
        }
        let badness = try archive.playerByte(.healthBadness, record: player)
        try require(Int(badness), 0...139, "health badness")
        let memberCount = Int(try archive.playerByte(.memberSlotCount, record: player))
        let survivors = Int(try archive.playerByte(.survivors, record: player))
        try require(memberCount, 1...5, "member slot count")
        try require(survivors, 1...memberCount, "living survivors")
        var members: [PartyMember] = []
        for slot in 0..<memberCount {
            let name = try archive.memberName(memberSlot: slot, wagonSlot: 0)
            guard OriginalRegistration.isValidName(name) else { throw ImportError.invalidName(memberSlot: slot) }
            let condition = try archive.condition(memberSlot: slot, record: player)
            guard condition == 255 || condition <= 9 else {
                throw ImportError.unsupported(field: "member \(slot) condition", value: Int(condition))
            }
            members.append(PartyMember(id: slot, name: name,
                health: condition == 9 ? 0 : [100.0,60,35,10][Int(badness) / 35],
                illness: condition < 9 ? OriginalHealth.conditionNames[Int(condition)] : nil,
                sickDays: Int(try archive.conditionDays(memberSlot: slot, record: player))))
        }
        guard members.filter(\.alive).count == survivors else { throw ImportError.inconsistent(field: "survivor count versus condition bytes") }
        let professions: [Profession] = [.banker,.blacksmith,.carpenter,.doctor,.farmer,.merchant,.saddlemaker,.teacher]
        var trip = Journey(profession: professions[occupation], difficulty: runtime.difficulty,
                           names: members.map(\.name), departureMonth: departureMonth, seed: runtime.randomSeed)
        trip.id = runtime.journeyID
        trip.members = members
        trip.daysElapsed = elapsed
        trip.pace = [.steady,.strenuous,.grueling][pace]
        trip.rations = [.filling,.meager,.bareBones][rations]
        trip.originalTiming = .init(speed: speed, huntTime: huntTime)
        let inventoryFields: [OriginalSaveArchive.PlayerWordField] = [.rawOxen,.clothing,.ammunition,.spareWheels,.spareAxles,.spareTongues,.food]
        for (supply, field) in zip(Supply.allCases, inventoryFields) {
            let value = Int(Int16(bitPattern: try archive.playerWord(field, record: player)))
            try require(value, 0...supply.capacity, "inventory \(supply.rawValue)")
            trip.inventory[supply] = value
        }
        trip.cash = Int(Int32(bitPattern: try archive.playerLong(.cashCents, record: player)))
        // Current native validation supports this bounded original overdraft range.
        try require(trip.cash, -990_000...1_000_000, "cash outside native representable range")
        trip.originalCashOverdraft = trip.cash < 0
        trip.delayDays = Int(archive.worldByte(.delayDays))
        var original = OriginalJourneyState()
        original.badness = badness
        original.auxiliary = try archive.playerByte(.auxiliaryHealth, record: player)
        original.pendingEventPenalty = try archive.playerByte(.pendingPenalty, record: player)
        // CODE6:02f4–0362 clears flags. CODE3:1952 restores only active bit1,
        // which is not modeled by the native daily scheduler. Counters survive.
        original.flags = 0
        original.restDays = archive.worldByte(.restDays)
        original.lastMovement = archive.worldByte(.lastMovement)
        original.lastSuccessfulHuntMileage = runtime.lastSuccessfulHuntMileage
        original.weather.category = archive.worldByte(.weatherCategory)
        original.weather.temperature = archive.worldByte(.temperatureCategory)
        original.weather.region = archive.worldByte(.climateRow)
        try require(Int(original.weather.category & 127), 0...9, "weather category")
        try require(Int(original.weather.temperature), 0...5, "temperature category")
        try require(Int(original.weather.region), 0...5, "climate row")
        original.weather.rain = archive.worldWord(.rainAccumulator)
        original.weather.snow = archive.worldWord(.snowAccumulator)
        original.weather.rainIncrement = archive.worldWord(.rainIncrement)
        original.weather.snowIncrement = archive.worldWord(.snowIncrement)
        original.weather.initialized = true
        trip.original = original
        switch original.weather.category & 127 {
        case 3,4: trip.weather = .rain
        case 5,6,8: trip.weather = .snow
        case 7,9: trip.weather = .storm
        case 1,2: trip.weather = .cold
        default: trip.weather = .sunny
        }
        let legLength = Int(archive.worldByte(.legLength))
        try require(remaining, 0...legLength, "remaining miles")
        let target = TrailCatalog.stops[destination + 1].id
        var route = ["independence"]
        var routeMiles = 0
        var expectedLeg = 0
        while route.last != target {
            let stop = TrailCatalog.stop(route.last!)
            let alternate = stop.id == "south-pass" && routeFlags & 1 != 0
                || stop.id == "blue-mountains" && routeFlags & 2 != 0
            guard let next = stop.routes.dropFirst(alternate ? 1 : 0).first,
                  !route.contains(next.destination) else { throw ImportError.inconsistent(field: "destination not on selected route") }
            route.append(next.destination)
            routeMiles += next.miles
            expectedLeg = next.miles
        }
        guard legLength == expectedLeg else { throw ImportError.inconsistent(field: "leg length versus selected route") }
        let miles = Int(archive.worldWord(.cumulativeMiles))
        guard miles == routeMiles - remaining else { throw ImportError.inconsistent(field: "cumulative miles versus selected route") }
        trip.miles = miles
        trip.legDistance = legLength
        trip.legProgress = legLength - remaining
        trip.destinationID = target
        trip.locationID = remaining > 0 ? route[route.count - 2] : target
        trip.visited = remaining > 0 ? Array(route.dropLast()) : route
        trip.phase = remaining > 0 ? .travel : (trip.location.river ? .river : .landmark)
        trip.miniGameReturnPhase = trip.phase
        let dimensions = OriginalRiverRules.Dimensions(depthHalfFeet: world[0x22a], widthTensFeet: world[0x22b])
        trip.originalRiverDimensions = dimensions
        trip.riverDepth = dimensions.depthFeet
        trip.riverWidth = dimensions.widthFeet
        if remaining == 0 && Int(Int16(bitPattern: archive.headerWord38)) == destination {
            trip.originalMapSuppressedLandmarkID = target
        }
        // No original export, journal synthesis, or source-byte mutations occur.
        let journal: JournalState
        if let used = archive.usedJournalBytes {
            do { journal = .decoded(try OriginalSaveJournal(usedBytes: used)) }
            catch let error as OriginalSaveJournal.DecodeError { journal = .undecodable(error) }
        } else { journal = .invalidUsedRange }
        return Result(archive: archive, journey: trip, compactJournal: journal)
    }

    private static func elapsedDays(year: Int, month: Int, day: Int, departureMonth: Int) throws -> Int {
        guard (1848...65535).contains(year) else { throw ImportError.unsupported(field: "wrapped or pre-departure year", value: year) }
        guard (1...12).contains(month) else { throw ImportError.unsupported(field: "calendar month", value: month) }
        let months = [31,28,31,30,31,30,31,31,30,31,30,31]
        let limit = months[month - 1] + (month == 2 && year % 4 == 0 ? 1 : 0)
        guard (1...limit).contains(day) else { throw ImportError.unsupported(field: "calendar day", value: day) }
        // Count years before year with original year0 included as a leap year.
        func ordinal(_ y: Int, _ m: Int, _ d: Int) -> Int {
            y * 365 + (y + 3) / 4 + months.prefix(m - 1).reduce(0,+)
                + (m > 2 && y % 4 == 0 ? 1 : 0) + d - 1
        }
        let elapsed = ordinal(year,month,day) - ordinal(1848,departureMonth,1)
        guard elapsed >= 0 else { throw ImportError.inconsistent(field: "calendar precedes departure") }
        return elapsed
    }
}
