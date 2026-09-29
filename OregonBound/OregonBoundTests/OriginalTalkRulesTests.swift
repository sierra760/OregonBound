import Foundation
import Testing
@testable import OregonBound

struct OriginalTalkRulesTests {
    @Test func firstClickUsesSecondQuoteThenWrapsAcrossLocations() throws {
        var state = OriginalTalkRules.State()
        var trip = Journey(seed: 123); trip.phase = .landmark
        let first = try #require(OriginalTalkRules.open(trip: trip, state: &state))
        #expect(first.resourceID == 3100 && first.quoteIndex == 2)
        #expect(first.portraitStringIndex == 2 && first.quoteStringIndex == 3)
        trip.locationID = "kansas"; trip.phase = .river
        #expect(OriginalTalkRules.open(trip: trip, state: &state)?.quoteIndex == 3)
        trip.locationID = "big-blue"
        #expect(OriginalTalkRules.open(trip: trip, state: &state)?.quoteIndex == 1)
        #expect(OriginalTalkRules.open(trip: trip, state: &state)?.quoteIndex == 2)
    }

    @Test func travelingUsesUpcomingDestinationIncludingForkBranches() throws {
        var trip = Journey(seed: 1); trip.phase = .travel
        trip.locationID = "south-pass"; trip.destinationID = "green"
        #expect(OriginalTalkRules.resourceID(in: trip) == 3109)
        trip.destinationID = "bridger"
        #expect(OriginalTalkRules.resourceID(in: trip) == 3108)
        trip.phase = .fork
        #expect(OriginalTalkRules.resourceID(in: trip) == 3107)
        trip.locationID = "blue-mountains"; trip.destinationID = "dalles"; trip.phase = .travel
        #expect(OriginalTalkRules.resourceID(in: trip) == 3116)
    }

    @Test func openingAndRenderingDoNotTouchJourneyOrRandomStream() throws {
        var state = OriginalTalkRules.State()
        var trip = Journey(seed: 654); trip.phase = .travel
        let snapshot = trip
        let selection = try #require(OriginalTalkRules.open(trip: trip, state: &state))
        let cursor = state.cursor
        let strings = ["1", "First", "6", "Second", "8", "Third"]
        #expect(OriginalTalkRules.content(selection: selection, strings: strings)?.portrait == 6)
        #expect(OriginalTalkRules.content(selection: selection, strings: strings)?.text == "Second")
        #expect(state.cursor == cursor && trip == snapshot)
    }

    @Test func stateIsSessionGlobalAndDoesNotResetOnNewJourney() throws {
        var state = OriginalTalkRules.State()
        var first = Journey(seed: 1); first.phase = .landmark
        #expect(OriginalTalkRules.open(trip: first, state: &state)?.quoteIndex == 2)
        var next = Journey(seed: 2); next.phase = .landmark
        #expect(OriginalTalkRules.open(trip: next, state: &state)?.quoteIndex == 3)
        #expect(OriginalTalkRules.State().cursor == 1)
    }

    @Test func malformedResourceOrSelectionFailsWithoutInventedQuote() {
        let selected = OriginalTalkRules.Selection(resourceID: 3100, quoteIndex: 2)
        #expect(OriginalTalkRules.content(selection: selected, strings: []) == nil)
        #expect(OriginalTalkRules.content(selection: selected, strings: ["0","a","9","b"]) == nil)
        #expect(OriginalTalkRules.content(selection: .init(resourceID: 3100, quoteIndex: Int.max), strings: []) == nil)
        #expect(OriginalTalkRules.content(selection: .init(resourceID: 0, quoteIndex: 1), strings: ["1","a"]) == nil)
    }

    @Test func invalidJourneyDestinationDoesNotAdvanceCounter() {
        var state = OriginalTalkRules.State()
        var trip = Journey(seed: 1); trip.phase = .travel; trip.destinationID = nil
        #expect(OriginalTalkRules.open(trip: trip, state: &state) == nil)
        #expect(state.cursor == 1)
        trip.destinationID = "missing"
        #expect(OriginalTalkRules.open(trip: trip, state: &state) == nil)
        #expect(state.cursor == 1)
    }
}
