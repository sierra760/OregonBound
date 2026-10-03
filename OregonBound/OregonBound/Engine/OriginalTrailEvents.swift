import Foundation

/// Single-wagon CODE16:309a–336a. Offsets exclude the CODE resource header.
/// All checks are independent and helper draws occur immediately, in order.
/// See docs/ORIGINAL_TRAIL_EVENTS.md, including the literal thief cash anomaly.
enum OriginalTrailEvents {
    typealias Draw = (_ bound: Int, _ codeOffset: Int) -> Int
    enum Action { case snowbound, snakebite, illness, foodAid, wildFruit, severeWeather, fogHail,
                       brokenPart, sickOx, brokenLimb, lostTrail, roughImpassable, fire,
                       wanderedOx, lostPerson, suppliesFound, thief, dryGround, spoilage, overloadedPart, overloadedOx }

    static func run(_ trip: inout Journey, draw: Draw) {
        trip.ensureOriginalState()
        guard !trip.livingMembers.isEmpty else { return }
        // The CD timer computes load before the daily event dispatch. Spoilage
        // and this day's other losses cannot change the cached overload checks.
        let cdWeight = trip.original?.cdWagonWeight ?? trip.inventory.cdWagonWeight
        var randomBreakage: Action?
        if trip.original!.weather.snow > 3000 { apply(.snowbound, to: &trip, draw: draw) }
        if trip.original!.weather.temperature >= 3 && draw(100, 0x30d6) < 4 { apply(.snakebite, to: &trip, draw: draw) }
        // CD CODE17:3bd2–3bf2: warm-weather spoilage follows snakebite.
        if trip.gameEdition == .macintoshCD12 && trip.original!.weather.temperature >= 3 && draw(100, 0x3be6) < 10 {
            apply(.spoilage, to: &trip, draw: draw)
        }
        if draw(100, 0x312c) < Int(trip.original!.badness) / 15 + 1 { apply(.illness, to: &trip, draw: draw) }
        if trip.totalFood == 0 && draw(100, 0x3160) < 5 { apply(.foodAid, to: &trip, draw: draw) }
        if (5...9).contains(trip.month) && draw(100, 0x319e) < 4 { apply(.wildFruit, to: &trip, draw: draw) }
        if [4, 6].contains(trip.original!.weather.category) ||
            (trip.original!.weather.temperature <= 1 && draw(100, 0x3200) < 15) { apply(.severeWeather, to: &trip, draw: draw) }
        if draw(100, 0x3216) < 6 { apply(.fogHail, to: &trip, draw: draw) }
        if draw(100, 0x322c) < (destinationIndex(trip) > 11 ? 7 : 4) {
            let action = [Action.brokenPart, .sickOx, .brokenLimb][draw(3, 0x326c)]
            randomBreakage = action
            apply(action, to: &trip, draw: draw)
        }
        if trip.gameEdition == .macintoshCD12 && !trip.livingMembers.isEmpty && cdWeight > 2750 {
            let threshold = 90 - (cdWeight - 2750) / 50
            if randomBreakage != .brokenPart && draw(100, 0x324e) > threshold {
                apply(.overloadedPart, to: &trip, draw: draw)
            }
            if randomBreakage != .sickOx && draw(100, 0x33ea) > threshold {
                apply(.overloadedOx, to: &trip, draw: draw)
            }
        }
        if draw(100, 0x32a0) < 2 { apply(.lostTrail, to: &trip, draw: draw) }
        if destinationIndex(trip) > 11 && draw(100, 0x32c8) < 5 { apply(.roughImpassable, to: &trip, draw: draw) }
        if draw(100, 0x32de) == 0 {
            apply([Action.fire, .wanderedOx, .lostPerson][draw(3, 0x32ec)], to: &trip, draw: draw)
        }
        let choice = draw(100, 0x3320)
        if choice < 2 { apply([Action.suppliesFound, .thief][choice], to: &trip, draw: draw) }
        if trip.original!.weather.rain == 0 && draw(2, 0x3358) != 0 { apply(.dryGround, to: &trip, draw: draw) }
    }

    static func destinationIndex(_ trip: Journey) -> Int {
        (TrailCatalog.stops.firstIndex { $0.id == trip.destinationID } ?? 1) - 1
    }

    /// CODE16:2f88: equal/lower requests don't even set the delay flag.
    static func delay(_ days: Int, in trip: inout Journey) {
        if days > trip.delayDays { trip.delayDays = days; trip.original?.flags |= 8 }
    }

    /// CODE16:2c64: valid draw1000 still falls back; dead draw1000 retries once.
    static func memberIndex(_ trip: Journey, draw: Draw) -> Int {
        if trip.livingMembers.count <= 1 { return 0 }
        var retries = 1000
        while true {
            let member = draw(trip.members.count - 1, 0x2c8c) + 1
            retries -= 1
            if trip.members[member].alive || retries < 0 { return retries > 0 ? member : 0 }
        }
    }

    /// CODE16:2cbc: selecting the sole active wagon calls R(1), which still
    /// consumes a QuickDraw sample. No active wagon skips the call entirely.
    private static func selectWagon(_ trip: Journey, draw: Draw) -> Bool {
        guard !trip.livingMembers.isEmpty else { return false }
        _ = draw(1, 0x2d12)
        return true
    }

    static func apply(_ action: Action, to trip: inout Journey, draw: Draw) {
        trip.ensureOriginalState()
        switch action {
        case .snowbound:
            delay(draw(10, 0x354a) + 1, in: &trip); record(12, in: &trip)
        case .severeWeather:
            // CD CODE17:41c8 checks dry ground before temperature. This helper
            // consumes no random draws; its caller retains the severe-weather gate.
            if trip.gameEdition == .macintoshCD12 && trip.original!.weather.rain < 5
                && trip.original!.weather.snow == 0 && (4...11).contains(destinationIndex(trip)) {
                delay(1, in: &trip); record(13, in: &trip); trip.original?.weather.category = 0x8a
            } else if trip.original!.weather.temperature <= 1 {
                delay(1, in: &trip); record(7, in: &trip); trip.original?.weather.category = 0x88
            } else if trip.original!.weather.temperature >= 4 {
                delay(1, in: &trip); record(8, in: &trip); trip.original?.weather.category = 0x87
            }
        case .fogHail:
            if destinationIndex(trip) > 11 && trip.original!.weather.temperature < 5 {
                if draw(2, 0x2f02) != 0 { delay(1, in: &trip); record(0, in: &trip) }
            } else if destinationIndex(trip) <= 11 && trip.original!.weather.temperature == 5 {
                record(1, in: &trip); trip.original?.weather.category = 0x89
            }
        case .lostTrail:
            delay(draw(5, 0x3064) + 1, in: &trip)
            record(draw(2, 0x3078) != 0 ? 2 : 3, in: &trip)
        case .roughImpassable:
            if draw(2, 0x3374) != 0 {
                if !trip.livingMembers.isEmpty { trip.original?.pendingEventPenalty = 10 }
                record(4, in: &trip)
            } else { delay(draw(10, 0x33de) + 1, in: &trip); record(5, in: &trip) }
        case .dryGround:
            let choice = draw(100, 0x381c)
            if choice < 40 { record(9, in: &trip) }
            else if trip.original!.weather.snow == 0 {
                if !trip.livingMembers.isEmpty { trip.original?.pendingEventPenalty = choice < 60 ? 20 : 10 }
                record(choice < 60 ? 11 : 10, in: &trip)
            }
        case .foodAid:
            trip.huntingFood = Int(UInt16(truncatingIfNeeded: trip.huntingFood + 30))
            record(20, in: &trip)
        case .wildFruit:
            if trip.huntingFood < trip.huntingFoodCapacity {
                trip.huntingFood = min(trip.huntingFoodCapacity, trip.huntingFood + 20); record(25, in: &trip)
            }
        case .spoilage:
            guard trip.gameEdition == .macintoshCD12, selectWagon(trip, draw: draw) else { return }
            let loss = trip.inventory.perishableFood / 10
            guard loss > 0 else { return }
            trip.inventory.perishableFood -= loss
            var quantities = [Int](repeating: 0, count: 8); quantities[7] = loss
            record(69, quantities: quantities, in: &trip)
        case .sickOx, .overloadedOx:
            guard (action == .overloadedOx || selectWagon(trip, draw: draw)), trip.inventory[.oxen] > 0 else { return }
            if trip.profession == .farmer && draw(2, 0x3444) != 0 { record(22, in: &trip) }
            else {
                trip.inventory[.oxen] -= 1
                record(trip.inventory[.oxen].isMultiple(of: 2) ? 24 : 23, in: &trip)
            }
        case .wanderedOx:
            guard selectWagon(trip, draw: draw) else { return }
            delay(draw(3, 0x2fd6) + 1, in: &trip); record(21, in: &trip)
        case .brokenPart, .overloadedPart:
            guard action == .overloadedPart || selectWagon(trip, draw: draw) else { return }
            let part = Supply.allCases[draw(3, 0x2b68) + 3]
            let event: Int
            // Draw before profession check, including for nonspecialists.
            if draw(2, 0x2b76) != 0 && trip.profession == .blacksmith { event = 30 }
            else if draw(2, 0x2bb2) != 0 && trip.profession == .carpenter { event = 30 }
            else if draw(2, 0x2bea) != 0 { event = 30 }
            else if trip.inventory[part] > 0 { trip.inventory[part] -= 1; event = 33 }
            else { trip.markBroken(part); trip.original?.flags &= ~2; event = 34 }
            record(event, part: part, in: &trip)
        case .snakebite, .brokenLimb, .lostPerson:
            guard selectWagon(trip, draw: draw) else { return }
            let member = memberIndex(trip, draw: draw)
            if action == .lostPerson {
                delay(draw(5, 0x3030) + 1, in: &trip); record(28, member: member, in: &trip)
            } else {
                let condition = action == .snakebite ? 2 : draw(2, 0x2ade)
                let duration = action == .snakebite ? 9 + draw(3, 0x3500) : 28 + draw(5, 0x2af2)
                trip.members[member].illness = OriginalHealth.conditionNames[condition]
                trip.members[member].sickDays = max(trip.members[member].sickDays, duration)
                record(action == .snakebite ? 29 : 26 + condition, member: member, in: &trip)
            }
        case .illness:
            guard !trip.livingMembers.isEmpty else { return }
            let member = memberIndex(trip, draw: draw)
            let condition = Int(OriginalHealth.conditionCode(illness: trip.members[member].illness, alive: trip.members[member].alive))
            trip.original?.pendingEventPenalty = 20
            if condition == 255 {
                let disease = 3 + draw(6, 0x2e94)
                trip.members[member].illness = OriginalHealth.conditionNames[disease]
                trip.members[member].sickDays = 9 + draw(3, 0x2ea4)
                record(34 + disease, member: member, in: &trip)
            } else if trip.profession == .doctor && draw(condition < 2 ? 2 : 3, 0x2e38) == 0 {
                record(52, member: member, in: &trip)
            } else {
                trip.members[member].health = 0
                let badness = min(trip.original!.badness, 105)
                trip.original?.badness = badness
                let event = condition == 2 ? 55 : (4...7).contains(condition) ? 52 + condition : 54
                record(trip.livingMembers.isEmpty ? 44 : event, member: member, in: &trip)
            }
        case .suppliesFound, .fire:
            guard selectWagon(trip, draw: draw) else { return }
            var quantities = [Int](repeating: 0, count: Inventory.itemCount(for: trip.gameEdition))
            if action == .suppliesFound {
                for i in 1...5 where draw(2, 0x29e0) != 0 {
                    let item = Supply.allCases[i]
                    quantities[i] = i == 2 ? draw(40, 0x29f8) + 20 : draw(3, 0x2a12) + 1
                    trip.inventory[item] = min(item.capacity, trip.inventory[item] + quantities[i])
                }
                record(63, quantities: quantities, in: &trip)
            } else {
                for i in 1..<quantities.count where draw(100, 0x1d44) < 50 {
                    quantities[i] = draw(trip.inventory[originalIndex: i] + 1, 0x1d62)
                    trip.inventory[originalIndex: i] -= quantities[i]
                }
                if quantities.contains(where: { $0 != 0 }) { record(65, quantities: quantities, in: &trip) }
            }
        case .thief:
            guard selectWagon(trip, draw: draw) else { return }
            let choice = draw(4, 0x3608)
            let index = choice == 3 ? 6 : choice
            let item = Supply.allCases[index]
            let quantity = trip.inventory[item]
            if quantity > 0 {
                var loss = 1 + draw(min(quantity, 100), quantity > 100 ? 0x3648 : 0x366e)
                if item == .oxen {
                    loss = (quantity + loss + 1) / 2 - (quantity + 1) / 2
                    if !loss.isMultiple(of: 2) { loss -= 1 }
                }
                guard loss > 0 else { return }
                trip.inventory[item] -= loss
                var quantities = [Int](repeating: 0, count: Inventory.itemCount(for: trip.gameEdition)); quantities[index] = loss
                record(64, quantities: quantities, in: &trip)
            } else if trip.cash > 100 {
                // Literal CODE16:3746–3770: no cent-to-dollar division or clamp.
                // Result may be negative; provenance permits bounded save decoding.
                // CD CODE17:4462 divides cents by100 before the small-cash draw.
                let cashBound = trip.gameEdition == .macintoshCD12 ? trip.cash / 100 : trip.cash
                let loss = (draw(trip.cash > 10000 ? 100 : cashBound, trip.cash > 10000 ? 0x3726 : 0x374e) + 1) * 100
                trip.cash = Int(Int32(truncatingIfNeeded: trip.cash - loss))
                if trip.cash < 0 { trip.originalCashOverdraft = true }
                record(64, cash: loss, in: &trip)
            }
        }
    }

    static func record(_ event: Int, member: Int = 0, part: Supply = .wheels,
                       quantities: [Int] = [Int](repeating: 0, count: 7), cash: Int = 0,
                       in trip: inout Journey) {
        let notification = trip.gameEdition == .macintoshCD12 ? notification(event: event, part: part) : nil
        if let text = OriginalJournalRules.weatherEvent(event, edition: trip.gameEdition) {
            trip.record(text, originalEvent: event, cdNotification: notification); return
        }
        // Older callers produce the seven common slots; CD appends an empty perishable slot.
        let packet = trip.gameEdition == .macintoshCD12 && quantities.count == 7 ? quantities + [0] : quantities
        if let text = OriginalJournalRules.supplyEvent(id: event,rawQuantities: packet,cashCents: cash,edition: trip.gameEdition) {
            trip.record(text, originalEvent: event, cdNotification: notification); return
        }
        // CODE16:14e0/1b50 packs the raft member index into event53's count bits.
        // Preserve that literal record field, including the original misleading count.
        if event == 53 { trip.record(OriginalJournalRules.drownedMembers(member), originalEvent: event); return }
        guard let template = OriginalJournalRules.currentWagonTemplate(event: event) else { return }
        let partName = part == .wheels ? "wagon wheel" : part == .axles ? "wagon axle" : "wagon tongue"
        trip.record(template.replacingOccurrences(of: "^0",with: trip.members[member].name)
            .replacingOccurrences(of: "^2",with: partName)
            .replacingOccurrences(of: "^6",with: trip.members[0].name), originalEvent: event, cdNotification: notification)
    }

    /// CODE17 sends a separate type14 packet after the journal write. Its code
    /// and parameter are not always the journal opcode/member parameter.
    private static func notification(event: Int, part: Supply) -> CDNotificationRules.Event? {
        switch event {
        case 0...13, 20, 21, 23, 24, 25, 28, 29, 63, 64, 65, 69:
            return .init(code: event)
        case 22: return .init(code: 23)
        case 26, 27: return .init(code: 26, parameter: event - 26)
        case 30...34:
            return .init(code: 47, parameter: part == .wheels ? 3 : part == .axles ? 4 : 5)
        case 37...42: return .init(code: 37, parameter: event - 34)
        default: return nil
        }
    }
}
