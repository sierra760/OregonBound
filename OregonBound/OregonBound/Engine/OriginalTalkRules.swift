import Foundation

/// Classic CODE3:37c6–3940 / CD CODE4:398a–3b2e. Authored pairs, never random.
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
        var edition: GameEdition = .macintosh11
        var soundResourceID: Int? {
            guard isValid, edition == .macintoshCD12 else { return nil }
            // CODE4:3a96: signed destination*10 + cursor +3110.
            return 3100 + (resourceID - 3100) * 10 + quoteIndex
        }
        var isValid: Bool { (3100...3117).contains(resourceID) && (1...3).contains(quoteIndex) }
        var portraitStringIndex: Int { isValid ? quoteIndex * 2 - 2 : -1 }
        var quoteStringIndex: Int { isValid ? quoteIndex * 2 - 1 : -1 }
    }
    struct Content: Equatable {
        let portrait: Int
        let text: String
        var edition: GameEdition = .macintosh11
        var portraitResourceID: Int { edition == .macintoshCD12 ? 16180 + portrait : 16080 }
        var portraitFrame: Int { edition == .macintoshCD12 ? 0 : portrait }
        var backgroundResourceID: Int { edition == .macintoshCD12 ? 16180 : 16080 }
        var backgroundFrame: Int { edition == .macintoshCD12 ? 0 : 9 }
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
        return Selection(resourceID: resource, quoteIndex: state.cursor, edition: trip.edition ?? .macintosh11)
    }

    static func content(selection: Selection, strings: [String]) -> Content? {
        guard selection.isValid, strings.indices.contains(selection.quoteStringIndex),
              let code = strings[selection.portraitStringIndex].utf8.first else { return nil }
        let portrait: Int
        if selection.edition == .macintoshCD12 {
            // CODE4:3a14 subtracts64 from the authored letter, selecting one of
            // 23 individual portrait resources. The shared background is16180.
            guard (UInt8(ascii: "A")...UInt8(ascii: "W")).contains(code) else { return nil }
            portrait = Int(code) - 64
        } else {
            // CODE3:3866 reads the first character minus48. Portrait6 is valid.
            guard (UInt8(ascii: "0")...UInt8(ascii: "8")).contains(code) else { return nil }
            portrait = Int(code) - 48
        }
        return Content(portrait: portrait, text: strings[selection.quoteStringIndex], edition: selection.edition)
    }
}
