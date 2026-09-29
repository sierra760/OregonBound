import Foundation

/// CODE3:37c6–3940. Quotes and portraits are authored pairs, never random.
/// A5−c66 is an application-session cursor initialized to1, incremented before
/// each Talk sidebar action, and not reset at landmarks or new journeys.
enum OriginalTalkRules {
    struct State: Equatable {
        private(set) var cursor = 1
        fileprivate mutating func advance() { cursor = cursor == 3 ? 1 : cursor + 1 }
    }
    struct Selection: Equatable {
        let resourceID: Int
        let quoteIndex: Int // Original one-based counter1…3.
        var isValid: Bool { (3100...3117).contains(resourceID) && (1...3).contains(quoteIndex) }
        var portraitStringIndex: Int { isValid ? quoteIndex * 2 - 2 : -1 }
        var quoteStringIndex: Int { isValid ? quoteIndex * 2 - 1 : -1 }
    }
    struct Content: Equatable {
        let portrait: Int
        let text: String
    }

    /// CODE3:3812 reads signed world+238 (the active destination), adds3101.
    /// At a stopped landmark the port's location is that same original index.
    static func resourceID(in trip: Journey) -> Int? {
        let id = trip.phase == .travel ? trip.destinationID : trip.locationID
        guard let index = TrailCatalog.stops.firstIndex(where: { $0.id == id }) else { return nil }
        return 3100 + index
    }

    /// Invoke on explicit Talk sidebar selection, including when already open.
    /// Rendering/reappearing a view must not call this or advance the cursor.
    static func open(trip: Journey, state: inout State) -> Selection? {
        guard trip.canCamp, let resource = resourceID(in: trip) else { return nil }
        state.advance()
        return Selection(resourceID: resource, quoteIndex: state.cursor)
    }

    static func content(selection: Selection, strings: [String]) -> Content? {
        guard selection.isValid, strings.indices.contains(selection.quoteStringIndex),
              let digit = strings[selection.portraitStringIndex].utf8.first,
              (UInt8(ascii: "0")...UInt8(ascii: "8")).contains(digit) else { return nil }
        // CODE3:3866 reads the first Pascal-string character and subtracts48.
        // Unlike Trade, Talk permits portrait6 because the resource chooses it.
        return Content(portrait: Int(digit - UInt8(ascii: "0")), text: strings[selection.quoteStringIndex])
    }
}
