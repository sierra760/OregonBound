import SwiftUI

/// Layout from DLOG/DITL 5000, 5400, 5600, 5700 and 5800.
struct OriginalTrailView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    var body: some View {
        OriginalWindow {
            ZStack(alignment: .topLeading) {
                originalPaper
                PixelArtwork(resource: 15000).frame(width: 52, height: 304).originalPaneFrame(width: 52, height: 304)
                PixelArtwork(resource: 15800).frame(width: 52, height: 304).originalPaneFrame(width: 52, height: 304).offset(x: 442)
                icon(5000, "Map", row: 0) { game.open(.map) }
                icon(6001, "Guide", row: 1) { game.open(.guide) }
                icon(5005, "Status", row: 2) { game.open(.supplies) }
                icon(6030, "Rations", row: 3) { game.open(.rations) }
                icon(5210, "Buy", row: 4) { game.open(.shop) }.disabled(!trip.canShop)
                icon(5004, "Trade", row: 0, right: true) { game.open(.trade) }
                icon(5800, "Talk", row: 1, right: true) { game.open(.talk) }
                icon(5801, "Rest", row: 2, right: true) { game.open(.rest) }
                icon(6050, "Pace", row: 3, right: true) { game.open(.pace) }
                icon(5803, "Hunt", row: 4, right: true) { game.startHunt() }
                if trip.phase == .travel || game.showingTravelMap {
                    OriginalTravelArtwork(trip: trip, moving: game.running && (trip.original?.flags ?? 0) & 12 == 0)
                        .frame(width: 262, height: 77).originalPaneFrame(width: 262, height: 77).offset(x: OriginalWindowLayout.centerOffsetX)
                    OriginalMapArtwork(trip: trip).frame(width: 262, height: 119).originalPaneFrame(width: 262, height: 119).offset(x: OriginalWindowLayout.centerOffsetX, y: 80)
                } else {
                    PixelArtwork(resource: trip.location.image, frame: trip.location.frame)
                        .id("\(trip.locationID)-\(trip.phase.rawValue)")
                        .frame(width: 262, height: 155).originalPaneFrame(width: 262, height: 155).offset(x: OriginalWindowLayout.centerOffsetX)
                    ZStack(alignment: .topLeading) {
                        OriginalText(text: trip.location.name)
                            .frame(width: 256, height: 17).offset(x: 3, y: 12)
                    }.frame(width: 262, height: 41, alignment: .topLeading)
                        .originalPaneFrame(width: 262, height: 41)
                        .offset(x: OriginalWindowLayout.centerOffsetX, y: 158)
                }
                conditions.frame(width: 119, height: 251, alignment: .topLeading)
                    .originalPaneFrame(width: 119, height: 251).offset(x: 320)
                OriginalPaneFrame(width: 119, height: 50).offset(x: 320, y: 254)
                OriginalButton(title: game.running ? "Time Out" : "Continue") { continueAction() }
                    .frame(width: 85, height: 24).offset(x: 337, y: 267)
                    .keyboardShortcut(.space, modifiers: [])
                OriginalJournalPane(entries: trip.journal, departureMonth: trip.departureMonth)
                    .id(trip.id).offset(x: CGFloat(OriginalJournalLayout.rootX) - OriginalWindowLayout.contentOrigin.x,
                                       y: CGFloat(OriginalJournalLayout.rootY) - OriginalWindowLayout.contentOrigin.y)
                if game.showingRouteDecision {
                    if trip.phase == .river { OriginalRiverOptions(game: game, trip: trip).frame(width: 262, height: 304).originalPaneFrame(width: 262, height: 304).offset(x: OriginalWindowLayout.centerOffsetX) }
                    else { OriginalRoutePane(game: game, trip: trip).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX) }
                }
                if let panel = game.panel, panel.usesTrailPane {
                    if panel == .talk, let selection = game.talkSelection {
                        OriginalTalkPane(selection: selection).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    } else if panel == .trade {
                        if trip.originalTradeSession == nil {
                            OriginalTradePane(game: game, trip: trip).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                        }
                    } else if panel == .guide {
                        OriginalGuidePane(trip: trip, audio: game.audio).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    } else if panel == .supplies {
                        OriginalStatusPane(trip: trip).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    } else if panel == .rest {
                        OriginalRestPane(game: game).frame(width: 262, height: 119).originalPaneFrame(width: 262, height: 119).offset(x: OriginalWindowLayout.centerOffsetX, y: 80)
                    } else {
                        OriginalChoicePane(game: game, trip: trip, panel: panel)
                            .id(panel).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    }
                }
            }.allowsHitTesting(trip.originalRiverOutcome == nil && trip.originalTradeSession == nil && game.huntResult == nil)
                .accessibilityHidden(trip.originalRiverOutcome != nil || trip.originalTradeSession != nil || game.huntResult != nil)
                .overlay(alignment: .topLeading) {
                    if let result = game.huntResult {
                        OriginalHuntResultPane(result: result) { game.huntResult = nil }.originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    }
                    if trip.originalTradeSession != nil {
                        OriginalTradePane(game: game, trip: trip).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
                    }
                    if let outcome = trip.originalRiverOutcome {
                        OriginalCrossingPane(trip: trip, outcome: outcome, prepareResult: game.prepareCrossingResult,
                                             complete: game.finishCrossing)
                            .id("\(trip.locationID)-\(outcome.requestedMethodRaw)")
                            .offset(x: OriginalWindowLayout.centerOffsetX)
                    }
                }
        }
    }

    private var conditions: some View {
        ZStack(alignment: .topLeading) {
            text("Conditions", x: 0, y: 6, width: 119, font: .bold14, alignment: .center)
            text(trip.dateText, x: 0, y: 24, width: 119, alignment: .center)
            PixelArtwork(resource: 15600, frame: weatherFrame).frame(width: 32, height: 32).offset(x: 12, y: 44)
            PixelArtwork(resource: 15600, frame: 10).frame(width: 28, height: 59).offset(x: 57, y: 42)
            let mercury = CGFloat(min(5, max(0, trip.originalTemperatureCategory)) * 6)
            Rectangle().fill(Color(red: 65280.0 / 65535, green: 0, blue: 1792.0 / 65535))
                .frame(width: 2, height: mercury).offset(x: 69, y: 87 - mercury)
            text("Hot\nWarm\nCold", x: 86, y: 52, width: 31)
            VStack(spacing: 0) {
                ForEach(Array(weatherLines.enumerated()), id: \.offset) { _, line in
                    OriginalText(text: line, font: .plain12)
                }
            }.frame(width: 48).offset(x: 5, y: 81)
            text("Distance", x: 0, y: 120, width: 119, font: .bold12, alignment: .center)
            pair("To Landmark:", "\(trip.phase == .travel ? trip.milesToNext : 0) mi.", y: 133)
            pair("Traveled:", "\(trip.miles) mi.", y: 145)
            text("Wagon", x: 0, y: 168, width: 119, font: .bold12, alignment: .center)
            pair("Pace:", trip.pace.rawValue, y: 180)
            pair("Rations:", trip.rations.rawValue, y: 192)
            pair("Food Left:", "\(trip.totalFood.formatted()) lbs.", y: 204)
            pair("Health:", trip.healthLabel, y: 216)
            pair("Wagon:", wagonStatus, y: 239)
        }
    }
    private var wagonStatus: String {
        let flags = trip.original?.flags ?? 0
        if trip.originalRiverOutcome != nil { return "Crossing River" }
        if flags & 4 != 0 { return "Resting" }
        if flags & 2 == 0 { return "Stopped" }
        return flags & 8 != 0 ? "Delayed" : "Moving"
    }
    private var weatherFrame: Int {
        min(9, max(0, trip.originalWeatherCategory))
    }
    private var weatherLines: [String] {
        let names = OriginalResources.strings(3012)
        guard names.count >= (weatherFrame + 1) * 2 else { return [trip.weather.rawValue] }
        return Array(names[(weatherFrame * 2)...(weatherFrame * 2 + 1)]).filter { !$0.isEmpty }
    }
    private func text(_ value: String, x: Int, y: Int, width: Int, font: BitmapFont? = .plain12, alignment: Alignment = .leading) -> some View {
        OriginalText(text: value, font: font).frame(width: CGFloat(width), alignment: alignment).offset(x: CGFloat(x), y: CGFloat(y))
    }
    private func pair(_ key: String, _ value: String, y: Int) -> some View {
        ZStack(alignment: .topLeading) {
            text(key, x: 2, y: y, width: 115)
            text(value, x: 2, y: y, width: 115, alignment: .trailing)
        }
    }
    private func icon(_ id: Int, _ label: String, row: Int, right: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    PixelArtwork(resource: 10129).frame(width: 42, height: 46)
                    PixelArtwork(resource: id).frame(width: 32, height: 32)
                }.frame(width: 42, height: 46).offset(x: 5, y: 2)
            }
            // The ribbon label is part of the sidebar artwork. Include it in
            // the same hit target instead of requiring a click on the picture.
            .frame(width: 52, height: 60, alignment: .topLeading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).offset(x: right ? 442 : 0, y: CGFloat(row * 60))
    }
    private func continueAction() {
        game.panel = nil
        if trip.phase == .river || trip.phase == .fork { game.showingRouteDecision = true }
        else { game.continueJourney() }
    }
}
