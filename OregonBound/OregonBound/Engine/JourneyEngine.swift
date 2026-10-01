import Foundation

enum CrossingMethod: String, CaseIterable, Identifiable {
    case ford = "Ford the river", caulk = "Caulk and float", ferry = "Take the ferry", guide = "Hire a guide"
    var id: String { rawValue }
}

struct ScoreLine: Identifiable {
    let id: String
    let points: Int
}

enum JourneyEngine {
    /// STR3002; engine tests do not depend on an application resource bundle.
    private static func originalLandmarkName(_ id: String) -> String {
        let names = ["Independence, Missouri", "the Kansas River Crossing", "the Big Blue River Crossing",
            "Fort Kearney", "Chimney Rock", "Fort Laramie", "Independence Rock", "South Pass", "Fort Bridger",
            "the Green River Crossing", "Soda Springs", "Fort Hall", "the Snake River Crossing", "Fort Boise",
            "Grande Ronde in the Blue Mountains", "Fort Walla Walla", "The Dalles"]
        guard let index = TrailCatalog.stops.firstIndex(where: { $0.id == id }), names.indices.contains(index) else {
            return TrailCatalog.stop(id).name
        }
        return names[index]
    }
    static func completeOutfitting(_ quantities: [Supply: Int], in trip: inout Journey) throws {
        guard trip.phase == .outfitting else { throw GameRuleError("Initial outfitting is already complete.") }
        var purchase = trip
        for item in Supply.allCases {
            let quantity = quantities[item, default: 0]
            guard quantity >= 0 else { throw GameRuleError("Enter a positive quantity.") }
            if item == .oxen && quantity > 20 { throw GameRuleError("You can buy at most 20 oxen here.") }
            if quantity > 0 { try buy(item, quantity: quantity, in: &purchase) }
        }
        purchase.phase = .departure
        trip = purchase
    }

    static func chooseDeparture(month: Int, in trip: inout Journey) throws {
        guard trip.phase == .departure, (3...8).contains(month) else { throw GameRuleError("Choose your starting month.") }
        trip.departureMonth = month
        trip.phase = .landmark
        initializeWeather(&trip)
        trip.journal.removeAll()
        OriginalTrailEvents.record(68,quantities: Supply.allCases.map { trip.inventory[$0] },cash: trip.cash,in: &trip)
    }

    static func price(_ item: Supply, quantity: Int = 1, in trip: Journey) -> Int {
        // Apply the regional percentage to the whole purchase before rounding cents.
        item.unitPrice * quantity * TrailCatalog.pricePercent(at: trip.locationID) / 100
    }

    static func buy(_ item: Supply, quantity: Int, in trip: inout Journey) throws {
        guard trip.canShop else { throw GameRuleError("You can only buy supplies at forts and in Independence.") }
        guard quantity > 0, quantity <= item.purchaseCapacity else { throw GameRuleError("Choose a quantity within your wagon’s capacity.") }
        let currentRaw = item == .oxen && trip.inventoryUnitsVersion == nil ? trip.inventory[item] * 2 : trip.inventory[item]
        let rawQuantity = item == .oxen ? quantity * 2 : quantity // CODE7:0x042a–0x0436
        guard rawQuantity <= item.capacity - currentRaw else { throw GameRuleError("Choose a quantity within your wagon’s capacity.") }
        let cost = price(item, quantity: quantity, in: trip)
        guard trip.cash >= cost else { throw GameRuleError("You do not have enough money for those supplies.") }
        trip.ensureOriginalState()
        trip.cash -= cost
        trip.inventory[item] += rawQuantity
    }

    static func depart(_ trip: inout Journey) throws {
        guard trip.phase == .outfitting || trip.phase == .landmark else { throw GameRuleError("Finish the current stop before continuing.") }
        if let missing = OriginalWagonContinuation.prepare(&trip) { throw GameRuleError(OriginalWagonContinuation.message(for: missing)) }
        guard trip.phase != .outfitting || trip.inventory[.food] > 0 else { throw GameRuleError("Matt says: You can’t set off on the trail without any oxen or food.") }
        trip.record(OriginalJournalRules.decision(.continueJourney))
        if trip.locationID == "dalles" || trip.location.routes.count > 1 {
            trip.phase = .fork
            return
        }
        guard let leg = trip.location.routes.first else { finish(&trip, won: true, reason: "You made it to the Willamette Valley."); return }
        setRoute(leg, in: &trip)
    }

    static func chooseRoute(_ destination: String, in trip: inout Journey) throws {
        guard trip.phase == .fork, trip.locationID != "dalles",
              let leg = trip.location.routes.first(where: { $0.destination == destination }) else { throw GameRuleError("That route is not available here.") }
        setRoute(leg, in: &trip)
        trip.record(OriginalJournalRules.decision(.trail(name: originalLandmarkName(destination),
            originalIndex: UInt8(TrailCatalog.stops.firstIndex { $0.id == destination } ?? 0))))
    }

    private static func setRoute(_ leg: TrailLeg, in trip: inout Journey) {
        trip.destinationID = leg.destination
        trip.legDistance = leg.miles
        trip.legProgress = 0
        trip.phase = .travel
        trip.ensureOriginalState()
        trip.original?.flags |= 2
    }

    /// CD CODE17:23f6 refreshes load even when a pulse does not advance a day.
    static func refreshWagonWeight(in trip: inout Journey) {
        guard trip.gameEdition == .macintoshCD12 else { return }
        trip.ensureOriginalState()
        trip.original?.cdWagonWeight = trip.inventory.cdWagonWeight
    }

    /// Compatibility entry point for an explicitly requested traveling day.
    /// The UI timer uses advanceActionDay so Time Out and pending rest survive.
    static func advanceDay(_ trip: inout Journey) {
        guard trip.phase == .travel else { return }
        trip.ensureOriginalState()
        trip.original?.flags |= 2
        advanceActionDay(in: &trip)
    }

    /// One eligible original daily update. Scheduler pulses may occur while
    /// stopped at a landmark/river or hunting if a rest command is still active.
    /// travelBlocked maps the original global bit16 without persisting UI state.
    @discardableResult
    static func advanceActionDay(in trip: inout Journey, travelBlocked: Bool = false) -> Bool {
        guard [.travel, .landmark, .river, .fork, .hunting, .rafting].contains(trip.phase),
              !trip.livingMembers.isEmpty else { return false }
        trip.ensureOriginalState()
        let remaining = trip.phase == .travel || trip.miniGameReturnPhase == .travel && trip.phase == .hunting ? trip.milesToNext : 0
        let flags = trip.original!.flags | (travelBlocked || trip.originalRiverOutcome != nil ? 16 : 0)
        let decision = OriginalActionScheduler.dayDecision(flags: flags,
            remainingMiles: remaining, minimumRawOxen: trip.inventory[.oxen])
        trip.original?.flags = decision.flags & ~16
        guard decision.advancesDate else { return false }
        guard let health = dailyNeeds(&trip, resting: false, preservingFlags: true), trip.phase != .finished else { return true }
        guard trip.phase == .travel else { return true }
        let state = trip.original!
        let destination = (TrailCatalog.stops.firstIndex(where: { $0.id == trip.destinationID }) ?? 1) - 1
        let traveled = OriginalDailyWeather.movement(
            flags: state.flags, pace: Int(trip.pace.originalIndex), destination: destination,
            oxen: trip.inventory[.oxen], conditions: health.terms.activeConditions,
            snow: state.weather.snow, remaining: trip.milesToNext)
        if state.flags & 2 != 0 && state.flags & 12 == 0 {
            trip.original?.lastMovement = UInt8(truncatingIfNeeded: traveled)
        }
        trip.miles += traveled
        trip.legProgress += traveled
        if trip.milesToNext == 0 { arrive(&trip, recordArrival: !decision.enteredResting) }
        return true
    }

    static func pauseTravel(in trip: inout Journey) {
        trip.ensureOriginalState()
        trip.original?.flags &= ~2
    }

    static func resumeTravel(in trip: inout Journey) {
        trip.ensureOriginalState()
        trip.original?.flags |= 2
    }

    private static func arrive(_ trip: inout Journey, recordArrival: Bool = true) {
        guard let destination = trip.destinationID else { return }
        trip.locationID = destination
        trip.original?.flags &= ~2
        if !trip.visited.contains(destination) { trip.visited.append(destination) }
        if recordArrival, destination != "oregon" {
            let template = OriginalJournalRules.currentWagonTemplate(event: 45)!
            trip.record(template.replacingOccurrences(of: "^5",with: originalLandmarkName(destination)))
        }
        if destination == "oregon" { finish(&trip, won: true, reason: "You made it to the Willamette Valley."); return }
        if trip.location.river {
            trip.phase = .river
            let dimensions = OriginalRiverRules.dimensions(destination: OriginalRiverRules.destinationIndex(trip),
                                                           rain: trip.original!.weather.rain)
            trip.originalRiverDimensions = dimensions
            trip.riverDepth = dimensions.depthFeet
            trip.riverWidth = dimensions.widthFeet
            trip.originalRiverOutcome = nil
        } else { trip.phase = .landmark }
    }

    private static func initializeWeather(_ trip: inout Journey) {
        trip.ensureOriginalState()
        var state = trip.original!
        guard !state.weather.initialized else { return }
        var random = OriginalRandom(seed: trip.randomState)
        OriginalDailyWeather.initialize(&state.weather, month: trip.month) { random.bounded($0) }
        trip.randomState = random.seed
        trip.original = state
    }

    /// Verified ordering: date, events, counters, weather, shared health; movement
    /// follows in advanceDay. Event dispatch is the recovered single-wagon flow;
    /// rest/hunting scheduling uses OriginalActionScheduler; the trade/rafting
    /// convenience paths below still use reconstructed direct day charges.
    @discardableResult
    private static func dailyNeeds(_ trip: inout Journey, resting: Bool, traveling: Bool = false, preservingFlags: Bool = false) -> OriginalHealth.Output? {
        guard trip.phase != .finished, !trip.livingMembers.isEmpty else { return nil }
        refreshWagonWeight(in: &trip)
        initializeWeather(&trip)
        if !preservingFlags {
            if traveling { trip.original?.flags |= 2 } else { trip.original?.flags &= ~2 }
            if resting {
                trip.original?.flags |= 4
                if trip.original!.restDays == 0 { trip.original?.restDays = 1 }
            }
        }
        trip.daysElapsed += 1
        if trip.original!.flags & 12 == 0 {
            var eventRandom = OriginalRandom(seed: trip.randomState)
            OriginalTrailEvents.run(&trip) { bound, _ in eventRandom.bounded(bound) }
            trip.randomState = eventRandom.seed
        }
        guard !trip.livingMembers.isEmpty else {
            finish(&trip, won: false, reason: "Everyone in your party has died.")
            return nil
        }
        var state = trip.original!
        if trip.brokenPart != nil || trip.inventory[.oxen] == 0 { state.flags &= ~2 }
        // Original counter bytes may remain dormant after load. Only the flag
        // activates a countdown; legacy inference belongs in ensureOriginalState.
        OriginalDailyWeather.tickCounters(flags: &state.flags, rest: &state.restDays, delay: &trip.delayDays)
        var random = OriginalRandom(seed: trip.randomState)
        OriginalDailyWeather.update(&state.weather, month: trip.month) { random.bounded($0) }
        trip.randomState = random.seed
        let input = OriginalHealth.Input(
            badness: state.badness, auxiliary: state.auxiliary,
            pendingEventPenalty: state.pendingEventPenalty,
            survivors: UInt8(trip.livingMembers.count), food: Int16(trip.inventory[.food]),
            perishableFood: Int16(trip.inventory.perishableFood), edition: trip.gameEdition,
            clothing: Int16(trip.inventory[.clothing]), rations: trip.rations.originalIndex,
            pace: trip.pace.originalIndex, stateFlags: state.flags,
            temperature: state.weather.temperature, weather: state.weather.category,
            members: trip.members.map { .init(condition: OriginalHealth.conditionCode(illness: $0.illness, alive: $0.alive),
                                              remainingDays: UInt8(clamping: $0.sickDays)) })
        let output = OriginalHealth.transition(input)
        state.auxiliary = output.auxiliary
        state.badness = output.storedBadnessBeforeThreshold
        trip.original = state
        trip.inventory[.food] = Int(output.food)
        if trip.gameEdition == .macintoshCD12 { trip.inventory.perishableFood = Int(output.perishableFood) }
        for i in trip.members.indices {
            trip.members[i].sickDays = Int(output.members[i].remainingDays)
            if output.members[i].condition == 255 { trip.members[i].illness = nil }
        }
        for index in output.recoveredMemberIndices { OriginalTrailEvents.record(36, member: index, in: &trip) }
        // Callback is before the caller's final clamp and pending reset. A death's
        // reduction to105 and this action's new pending20 are overwritten here.
        if output.thresholdCrossed { illnessAction(&trip) }
        trip.original?.badness = output.badness
        trip.original?.pendingEventPenalty = 0
        trip.synchronizeSharedHealth()
        switch state.weather.category {
        case 3, 4: trip.weather = .rain
        case 5, 6, 8: trip.weather = .snow
        case 7, 9, 10: trip.weather = .storm
        case 1, 2: trip.weather = .cold // legacy display only; UI uses exact category getter
        default: trip.weather = .sunny
        }
        if trip.livingMembers.isEmpty { finish(&trip, won: false, reason: "Everyone in your party has died.") }
        return output
    }

    private static func illnessAction(_ trip: inout Journey) {
        var random = OriginalRandom(seed: trip.randomState)
        OriginalTrailEvents.apply(.illness, to: &trip) { bound, _ in random.bounded(bound) }
        trip.randomState = random.seed
    }

    /// Queue only. Original command3 preserves moving2 and delay8; its
    /// counter-zero cleanup day is processed later by advanceActionDay.
    static func beginRest(days: Int, in trip: inout Journey) throws {
        guard trip.canCamp, (1...9).contains(days) else { throw GameRuleError("Choose between one and nine days to rest.") }
        trip.ensureOriginalState()
        trip.original?.restDays = UInt8(days)
        trip.original?.flags |= 4
        trip.record(OriginalJournalRules.decision(.rest(UInt8(days))))
    }

    /// Synchronous non-UI convenience. Production UI uses beginRest and the
    /// scheduler; this drains all N+1 original updates, including cleanup.
    static func rest(days: Int, in trip: inout Journey) throws {
        try beginRest(days: days, in: &trip)
        while trip.phase != .finished && trip.original!.flags & 4 != 0 {
            guard advanceActionDay(in: &trip) else { break }
        }
    }

    static func repair(_ trip: inout Journey) throws {
        guard trip.canCamp, !trip.damagedParts.isEmpty else { throw GameRuleError("Your wagon does not need a repair.") }
        if let missing = OriginalWagonContinuation.prepare(&trip) {
            throw GameRuleError(OriginalWagonContinuation.message(for: missing))
        }
    }

    static func trade(give: Supply, quantity: Int, receive: Supply, in trip: inout Journey) throws {
        guard trip.canCamp, give != receive, quantity > 0, quantity <= trip.displayQuantity(give) else { throw GameRuleError("Choose supplies you have available to trade.") }
        trip.ensureOriginalState()
        let rawGiven = give == .oxen ? quantity * 2 : quantity
        guard rawGiven <= trip.inventory[give] else { throw GameRuleError("You do not have a complete pair of oxen for that trade.") }
        // Reconstructed exchange ratio; prices and UI quantities use pairs while
        // inventory/animal losses use individual raw oxen. Convert both sides.
        let received = quantity * give.unitPrice * 3 / (receive.unitPrice * 4)
        let rawReceived = receive == .oxen ? received * 2 : received
        guard received > 0, rawReceived <= receive.capacity - trip.inventory[receive] else { throw GameRuleError("That trade is too small or exceeds your wagon’s capacity.") }
        trip.inventory[give] -= rawGiven
        trip.inventory[receive] += rawReceived
        var given = [Int](repeating: 0,count: 7), obtained = given
        given[Supply.allCases.firstIndex(of: give)!] = rawGiven
        obtained[Supply.allCases.firstIndex(of: receive)!] = rawReceived
        // STR1505[10]; legacy exchange arithmetic above remains a compatibility path.
        trip.record("You traded " + OriginalJournalRules.supplyList(rawQuantities: given)
            + " for " + OriginalJournalRules.supplyList(rawQuantities: obtained) + ".")
        dailyNeeds(&trip, resting: true)
    }

    static func availableCrossings(in trip: Journey) -> [CrossingMethod] {
        OriginalRiverRules.availableMethods(destination: OriginalRiverRules.destinationIndex(trip))
    }

    static func cross(_ method: CrossingMethod, in trip: inout Journey) throws {
        try beginCrossing(method, in: &trip)
        prepareCrossingResult(in: &trip)
        completeCrossing(in: &trip)
    }

    static func beginCrossing(_ method: CrossingMethod, in trip: inout Journey) throws {
        guard trip.originalRiverOutcome == nil else { throw GameRuleError("Finish the current crossing first.") }
        guard trip.phase == .river else { throw GameRuleError("This river crossing is not active.") }
        let destination = OriginalRiverRules.destinationIndex(trip)
        let dimensions = OriginalRiverRules.dimensions(in: trip)
        if let rejection = OriginalRiverRules.rejection(method, destination: destination,
            depthHalfFeet: Int(dimensions.depthHalfFeet), cash: trip.cash, clothing: trip.inventory[.clothing]) {
            throw GameRuleError(rejection)
        }
        trip.ensureOriginalState()
        // CODE18:0d14 charges before choosing the outcome. Crossing adds no
        // travel days or food cost; CODE16:1ab0–1ad0 returns at a stopped river.
        if method == .ferry { trip.cash -= 500 }
        if method == .guide { trip.inventory[.clothing] -= 3 }
        trip.record(OriginalJournalRules.decision(.crossing(OriginalRiverRules.methodRaw(method))))
        var random = OriginalRandom(seed: trip.randomState)
        let outcome = OriginalRiverRules.choose(method: method, destination: destination,
            dimensions: dimensions, rain: trip.original!.weather.rain, edition: trip.gameEdition) {
                bound, _ in random.bounded(bound)
            }
        trip.randomState = random.seed
        trip.originalRiverOutcome = outcome
    }

    /// Result creation is a separate serialized action after animation. Never
    /// restore the choice-time seed: intervening rest uses this same stream.
    @discardableResult
    static func prepareCrossingResult(in trip: inout Journey) -> OriginalRiverRules.Outcome? {
        guard trip.phase == .river, !trip.livingMembers.isEmpty,
              let choice = trip.originalRiverOutcome else { return nil }
        guard !choice.isPrepared else { return choice }
        trip.ensureOriginalState()
        var random = OriginalRandom(seed: trip.randomState)
        let result = OriginalRiverRules.prepareResult(choice,
            destination: OriginalRiverRules.destinationIndex(trip), dimensions: OriginalRiverRules.dimensions(in: trip),
            rain: trip.original!.weather.rain, inventory: trip.inventory.rawQuantities(for: trip.gameEdition),
            living: trip.members.map(\.alive), edition: trip.gameEdition,
            wagonWeight: trip.original?.cdWagonWeight ?? trip.inventory.cdWagonWeight) { bound, _ in random.bounded(bound) }
        trip.randomState = random.seed
        trip.originalRiverOutcome = result
        return result
    }

    /// Apply the pending record once, after scene and result-pane completion
    /// (CODE3:23c2 ->CODE18:11c0 ->CODE16:12f2). Safe to call again after resume.
    @discardableResult
    static func completeCrossing(in trip: inout Journey) -> OriginalRiverRules.Outcome? {
        guard trip.phase == .river, let outcome = trip.originalRiverOutcome, outcome.isPrepared else { return nil }
        trip.originalRiverOutcome = nil
        trip.originalMapSuppressedLandmarkID = trip.locationID
        // CODE16:12f2–143e applies the completed loss record, not per-person
        // illness death handling: river deaths do not lower shared badness to105.
        for index in outcome.losses.indices {
            trip.inventory[originalIndex: index] = max(0, trip.inventory[originalIndex: index] - outcome.losses[index])
        }
        if outcome.losses.contains(where: { $0 != 0 }) {
            OriginalTrailEvents.record(66, quantities: outcome.losses, in: &trip)
        }
        let drowned = outcome.drownedMembers.filter { trip.members[$0].alive }
        for member in drowned { trip.members[member].health = 0 }
        if trip.livingMembers.isEmpty {
            OriginalTrailEvents.record(44, in: &trip)
            finish(&trip, won: false, reason: "No one survived the river crossing.")
        } else {
            if !drowned.isEmpty {
                let count = drowned.count
                trip.record(OriginalJournalRules.drownedMembers(count), originalEvent: 53)
            }
            trip.phase = .landmark
        }
        return outcome
    }

    static func beginHunt(_ trip: inout Journey) throws {
        guard trip.canCamp, !trip.livingMembers.isEmpty else { throw GameRuleError("Hunting is not available during this activity.") }
        let eligibility = trip.huntEligibility
        guard eligibility == .allowed else {
            throw GameRuleError(eligibility.notice(landmarkName: originalLandmarkName(trip.locationID))
                ?? "Another activity must finish before hunting.")
        }
        let previousPhase = trip.phase
        // CODE16 command16 stops movement but charges no date/food/weather.
        pauseTravel(in: &trip)
        trip.miniGameReturnPhase = previousPhase
        trip.record(OriginalJournalRules.decision(.hunt))
        trip.phase = .hunting
    }

    /// Native recovery when the selected installation cannot supply its hunt assets.
    /// Returning from the error pane does not submit a hunting result or charge rest.
    static func cancelHunt(_ trip: inout Journey) throws {
        guard trip.phase == .hunting else { throw GameRuleError("This hunt is not active.") }
        trip.phase = trip.miniGameReturnPhase
    }

    static func finishHunt(food: Int, shots: Int, in trip: inout Journey) throws {
        let input = OriginalHuntSession.Input(destination: 0, month: 1, weatherCategory: 0,
            snow: false, mileage: trip.miles, lastSuccessfulHuntMileage: trip.original?.lastSuccessfulHuntMileage ?? 0,
            ammunition: trip.inventory[.bullets], survivors: trip.livingMembers.count,
            currentFood: trip.huntingFood, foodCapacity: trip.huntingFoodCapacity,
            timeSetting: 3, originalDisplayFlag: true)
        let result = trip.gameEdition == .macintoshCD12
            ? CDHuntSession.settle(foodShot: food,shots: shots,input: input)
            : OriginalHuntSession.settle(foodShot: food,shots: shots,input: input)
        try finishHunt(result: result,in: &trip)
    }

    @discardableResult
    static func finishHunt(result: OriginalHuntSession.Result, in trip: inout Journey) throws -> OriginalHuntSession.Result {
        guard trip.phase == .hunting, result.foodShot >= 0, result.foodCarried >= 0,
              result.foodCarried <= result.foodShot,
              (trip.gameEdition == .macintoshCD12 ? [125,250] : [100,200]).contains(result.carryLimit),
              result.foodCarried <= result.carryLimit,
              (0...min(20,trip.inventory[.bullets])).contains(result.shots)
        else { throw GameRuleError("This hunt is not active or its result is invalid.") }
        // CODE13:03b4 freezes carrying capacity at hunt startup;04c2/04cc
        // read live mileage and food after any interleaved resting days.
        let settled = OriginalHuntSession.Result(foodShot: result.foodShot,
            foodCarried: min(result.foodShot, result.carryLimit, max(0, trip.huntingFoodCapacity - trip.huntingFood)),
            shots: result.shots,
            lastSuccessfulHuntMileage: result.foodShot > 0 ? trip.miles : result.lastSuccessfulHuntMileage,
            carryLimit: result.carryLimit)
        trip.huntingFood += settled.foodCarried
        trip.inventory[.bullets] -= settled.shots
        trip.phase = trip.miniGameReturnPhase
        trip.ensureOriginalState()
        trip.original?.lastSuccessfulHuntMileage = settled.lastSuccessfulHuntMileage
        // CODE16 action6 queues this before CODE6 presents the outcome dialog.
        trip.original?.restDays &+= 1
        trip.original?.flags |= 4
        trip.record(OriginalJournalRules.huntReturn(food: settled.foodCarried))
        return settled
    }

    static func takeBarlowRoad(_ trip: inout Journey) throws {
        guard trip.phase == .fork, trip.locationID == "dalles" else { throw GameRuleError("The Barlow Toll Road begins at The Dalles.") }
        guard trip.cash >= 500 else { throw GameRuleError("You need $5.00 for the Barlow Toll Road. You can take the Columbia River instead.") }
        trip.cash -= 500
        setRoute(TrailLeg(destination: "oregon", miles: 100), in: &trip)
        trip.record(OriginalJournalRules.decision(.trail(name: "take the Barlow Toll Road",originalIndex: 17)))
    }

    static func beginRaft(_ trip: inout Journey) throws {
        guard trip.phase == .fork, trip.locationID == "dalles" else { throw GameRuleError("You can begin rafting at The Dalles.") }
        trip.ensureOriginalState()
        // CODE16:1146–11d0 commands10/11; CODE17:006a copies wagon before intro.
        trip.originalRaftState = .init(input: .init(
            inventory: trip.inventory.rawQuantities(for: trip.gameEdition),living: trip.members.map(\.alive),
            names: trip.members.map(\.name),rain: Int(trip.original?.weather.rain ?? 0)))
        trip.destinationID = "oregon"
        trip.legDistance = 100
        trip.legProgress = 0
        trip.original?.flags &= ~2
        trip.phase = .rafting
        trip.record(OriginalJournalRules.decision(.trail(name: "raft down the Columbia River",originalIndex: 18)))
    }

    static func originalRaftInput(_ trip: Journey) -> OriginalRaftSession.Input {
        var input = trip.originalRaftState?.input ?? .init(
            inventory: trip.inventory.rawQuantities(for: trip.gameEdition),living: trip.members.map(\.alive),
            names: trip.members.map(\.name),rain: Int(trip.original?.weather.rain ?? 0))
        // Rain is read at scene creation, after intro; inventory uses the earlier copy.
        input.rain = Int(trip.original?.weather.rain ?? 0)
        return input
    }

    /// CODE3:1e66–1f18 builds command61 when the scene ends, before onshore wait.
    static func prepareRaftLanding(result: OriginalRaftSession.Result, in trip: inout Journey) throws {
        if trip.phase == .finished { trip.originalRaftState = nil; return }
        guard trip.phase == .rafting, var state = trip.originalRaftState else {
            throw GameRuleError("This raft trip is not active.")
        }
        if let prepared = state.preparedResult {
            guard prepared == result else { throw GameRuleError("This raft trip already received a different result.") }
            return
        }
        guard result.initialInventory == state.input.inventory,
              result.initialLiving == state.input.living,
              result.remainingInventory.count == Inventory.itemCount(for: trip.gameEdition),
              zip(result.remainingInventory,result.initialInventory).allSatisfy({ $0 >= 0 && $0 <= $1 }),
              Set(result.drownedMembers).count == result.drownedMembers.count,
              result.drownedMembers.allSatisfy({ state.input.living.indices.contains($0) && state.input.living[$0] })
        else { throw GameRuleError("The raft result does not match its original wagon snapshot.") }
        state.preparedResult = result
        // Signed subtraction at CODE3:1ecc–1eee uses LIVE inventory, not startup copy.
        // Food consumed while rafting can therefore produce a negative loss word.
        state.commandQuantities = result.remainingInventory.indices.map { index in
            Int(Int16(truncatingIfNeeded: trip.inventory[originalIndex: index]-result.remainingInventory[index]))
        }
        trip.originalRaftState = state
    }

    /// CODE6:25c6 sends command61 at first onshore timer; CODE16:1442 applies it.
    /// Returns false for a duplicate or when a separate daily death has already ended play.
    @discardableResult static func applyRaftLosses(result: OriginalRaftSession.Result, in trip: inout Journey) throws -> Bool {
        if trip.phase == .finished { trip.originalRaftState = nil; return false }
        try prepareRaftLanding(result: result,in: &trip)
        guard var state = trip.originalRaftState, let quantities = state.commandQuantities else {
            throw GameRuleError("This raft trip has no prepared settlement.")
        }
        if state.appliedResult != nil { return false }
        trip.ensureOriginalState()
        state.appliedResult = result
        trip.originalRaftState = state
        // CODE16:146a–148a subtracts the earlier signed packet from CURRENT quantities.
        // Rest during the onshore wait is retained; rest before packet creation may be restored.
        for index in quantities.indices {
            trip.inventory[originalIndex: index] = max(0,trip.inventory[originalIndex: index]-quantities[index])
        }
        if quantities.contains(where: { $0 != 0 }) { OriginalTrailEvents.record(66,quantities: quantities,in: &trip) }
        for member in result.drownedMembers.sorted() where trip.members[member].alive {
            let survivingBadness = min(trip.healthBadness,105)
            trip.original?.badness = survivingBadness
            trip.members[member].health = 0
            OriginalTrailEvents.record(trip.livingMembers.isEmpty ? 44 : 53,member: member,in: &trip)
        }
        if trip.livingMembers.isEmpty {
            trip.originalRaftState = nil
            finish(&trip,won: false,reason: "No one survived rafting down the Columbia River.")
        }
        return true
    }

    /// CODE6:24f0–2570: next60-tick onshore callback enters the ending.
    static func completeRaftLanding(in trip: inout Journey) throws {
        if trip.phase == .finished { trip.originalRaftState = nil; return }
        guard trip.phase == .rafting, trip.originalRaftState?.appliedResult != nil else {
            throw GameRuleError("The raft losses have not been submitted yet.")
        }
        trip.originalRaftState = nil
        if trip.livingMembers.isEmpty {
            finish(&trip,won: false,reason: "No one survived rafting down the Columbia River.")
        } else {
            trip.locationID = "oregon"
            if !trip.visited.contains("oregon") { trip.visited.append("oregon") }
            finish(&trip,won: true,reason: "You landed safely in the Willamette Valley.")
        }
    }

    /// Synchronous simulation compatibility. Runtime uses the two separate callbacks.
    static func finishRaft(result: OriginalRaftSession.Result, randomSeed: UInt32, in trip: inout Journey) throws {
        guard trip.phase != .finished else { trip.originalRaftState = nil; return }
        _ = try applyRaftLosses(result: result,in: &trip)
        trip.randomState = randomSeed
        try completeRaftLanding(in: &trip)
    }

    static func finish(_ trip: inout Journey, won: Bool, reason: String) {
        guard trip.phase != .finished else { return }
        trip.phase = .finished
        trip.originalRiverOutcome = nil
        trip.originalRaftState = nil
        trip.original?.flags = 0
        trip.won = won
        trip.originalEndingStage = .arrival
        trip.finishReason = reason
    }

    static func scoreLines(_ trip: Journey) -> [ScoreLine] {
        guard trip.won else { return [] }
        var lines = [
            ScoreLine(id: "People arriving", points: trip.livingMembers.count * OriginalHealth.scorePerSurvivor(badness: trip.healthBadness)),
            ScoreLine(id: "Wagon", points: 50),
            ScoreLine(id: "Oxen", points: ((trip.inventory[.oxen] + 1) / 2) * 4),
            ScoreLine(id: "Spare wagon parts", points: (trip.inventory[.wheels] + trip.inventory[.axles] + trip.inventory[.tongues]) * 2),
            ScoreLine(id: "Clothing", points: trip.inventory[.clothing] * 2),
            ScoreLine(id: "Bullets", points: trip.inventory[.bullets] / 50),
            ScoreLine(id: trip.gameEdition == .macintoshCD12 ? "Non-perishable food" : "Food", points: trip.inventory[.food] / 25)
        ]
        if trip.gameEdition == .macintoshCD12 {
            lines.append(ScoreLine(id: "Perishable food", points: trip.inventory.perishableFood / 25))
        }
        lines.append(ScoreLine(id: "Money", points: trip.cash / 500))
        return lines
    }

    // CODE 10: multiply subtotal by the occupation's half-unit factor, then round up.
    static func score(_ trip: Journey) -> Int { (scoreLines(trip).reduce(0) { $0 + $1.points } * trip.profession.scoreHalfMultiplier + 1) / 2 }
}
