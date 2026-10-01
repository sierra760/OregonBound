import Foundation

/// CD CODE4:27bc–2f4a. The model publishes a world snapshot separately from
/// the Conditions pane's timer. Presentation state is not part of a saved game.
struct CDConditionsPresentation {
    struct Styles: Equatable {
        var food: Bool
        var health: Bool
        var weight: Bool
        var wagon: Bool
    }

    private(set) var snapshot: Journey?
    private(set) var revision: UInt32 = 0
    private(set) var warningPhase = false
    private var observedRevision: UInt8 = 0
    private var nextWarningPhase = false
    private var visible = false

    /// Called when the model publishes, including timer pulses with no new day.
    mutating func publish(_ trip: Journey) {
        precondition(trip.gameEdition == .macintoshCD12)
        snapshot = trip
        revision &+= 1
    }

    /// Revealing the pane performs a full draw but does not consume its timer's
    /// revision marker. Both source globals survive switching journeys.
    mutating func show(_ trip: Journey) {
        if snapshot?.id != trip.id { publish(trip) }
        visible = true
        redraw()
    }

    mutating func hide() { visible = false }

    /// Called by the 15-tick pane timer. Hidden panes consume the revision
    /// without drawing; blocked dispatch does neither. The source compares a
    /// byte with the full long counter, so after 255 it redraws on every poll.
    @discardableResult
    mutating func poll(active: Bool = true, modalBlocked: Bool = false) -> Bool {
        guard active, !modalBlocked, UInt32(observedRevision) != revision else { return false }
        observedRevision = UInt8(truncatingIfNeeded: revision)
        guard visible, snapshot != nil else { return false }
        redraw()
        return true
    }

    private mutating func redraw() {
        warningPhase = nextWarningPhase
        nextWarningPhase.toggle()
    }

    static func styles(for trip: Journey, warningPhase: Bool) -> Styles {
        let weight = trip.original?.cdWagonWeight ?? trip.inventory.cdWagonWeight
        let wagon = wagonStatus(for: trip)
        return Styles(food: warningPhase && trip.totalFood <= 100,
                      health: warningPhase && trip.healthBadness >= 105,
                      weight: warningPhase && weight >= 2750,
                      wagon: !warningPhase && (wagon == "Resting" || wagon == "Delayed"))
    }

    static func wagonStatus(for trip: Journey) -> String {
        let flags = trip.original?.flags ?? 0
        if trip.originalRiverOutcome != nil { return "Crossing River" }
        if flags & 4 != 0 { return "Resting" }
        if flags & 2 == 0 { return "Stopped" }
        return flags & 8 != 0 ? "Delayed" : "Moving"
    }
}
