import SwiftUI
import ImageIO

/// Layout from DLOG/DITL 5000, 5400, 5600, 5700 and 5800.
struct OriginalTrailView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    var body: some View {
        OriginalWindow {
            ZStack(alignment: .topLeading) {
                originalPaper
                PixelArtwork(resource: 15000, monochromeResource: 5000).frame(width: 52, height: 304).originalPaneFrame(width: 52, height: 304)
                PixelArtwork(resource: 15800, monochromeResource: 5800).frame(width: 52, height: 304).originalPaneFrame(width: 52, height: 304).offset(x: 442)
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
                    OriginalLandmarkArtwork(trip: trip, artwork: game.cdLandmark.artwork)
                        .id(trip.id)
                        .frame(width: 262, height: 155).originalPaneFrame(width: 262, height: 155).offset(x: OriginalWindowLayout.centerOffsetX)
                    ZStack(alignment: .topLeading) {
                        OriginalText(text: trip.location.name)
                            .frame(width: 256, height: 17).offset(x: 3, y: 12)
                    }.frame(width: 262, height: 41, alignment: .topLeading)
                        .originalPaneFrame(width: 262, height: 41)
                        .offset(x: OriginalWindowLayout.centerOffsetX, y: 158)
                }
                if let notice = game.cdNotification, game.notificationPaneVisible {
                    CDNotificationPane(game: game, notice: notice)
                        .originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
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
                        OriginalGuidePane(trip: trip, audio: game.audio, initialPage: game.guidePage).id(game.guidePage).frame(width: 262, height: 199).originalPaneFrame(width: 262, height: 199).offset(x: OriginalWindowLayout.centerOffsetX)
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
                        OriginalCrossingPane(trip: trip, outcome: outcome, audio: game.audio, prepareResult: game.prepareCrossingResult,
                                             complete: game.finishCrossing)
                            .id("\(trip.locationID)-\(outcome.requestedMethodRaw)")
                            .offset(x: OriginalWindowLayout.centerOffsetX)
                    }
                }
        }
        .onAppear { if conditionsVisible { game.showConditions() } }
        .onDisappear { game.setConditionsVisible(false) }
        .onChange(of: conditionsVisible) { game.setConditionsVisible($0) }
    }

    private var conditionsVisible: Bool { game.panel?.usesTrailPane != false }
    private var conditionsTrip: Journey {
        guard trip.gameEdition == .macintoshCD12,
              let displayed = game.cdConditions.displayedSnapshot, displayed.id == trip.id else { return trip }
        return displayed
    }
    private var conditions: some View {
        let trip = conditionsTrip
        let emphasis = trip.gameEdition == .macintoshCD12
            ? CDConditionsPresentation.styles(for: trip, warningPhase: game.cdConditions.warningPhase) : nil
        return ZStack(alignment: .topLeading) {
            text("Conditions", x: 0, y: 6, width: 119, font: .bold14, alignment: .center)
            text(trip.dateText, x: 0, y: 24, width: 119, alignment: .center)
            let weather = Self.weatherArtwork(edition: trip.gameEdition, category: weatherFrame)
            PixelArtwork(resource: weather.resource, monochromeResource: weather.resource == 20300 ? 20300 : 5600, frame: weather.frame).frame(width: 32, height: 32).offset(x: 12, y: 44)
            PixelArtwork(resource: 15600, monochromeResource: 5600, frame: 10).frame(width: 28, height: 59).offset(x: 57, y: 42)
            let mercury = CGFloat(min(5, max(0, trip.originalTemperatureCategory)) * 6)
            Rectangle().fill(OriginalResources.colorMode == .monochrome ? .black : Color(red: 65280.0 / 65535, green: 0, blue: 1792.0 / 65535))
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
            pair("Food Left:", "\(trip.totalFood.formatted()) lbs.", y: 204, valueBold: emphasis?.food == true)
            pair("Health:", trip.healthLabel, y: 216, valueBold: emphasis?.health == true)
            if trip.gameEdition == .macintoshCD12 {
                let weight = trip.original?.cdWagonWeight ?? trip.inventory.cdWagonWeight
                pair("Weight:", "\(OriginalStoreRules.grouped(weight)) lbs.", y: 228, valueBold: emphasis?.weight == true)
            }
            pair("Wagon:", wagonStatus, y: 239, valueBold: emphasis?.wagon == true)
        }
    }
    private var wagonStatus: String {
        let trip = conditionsTrip
        let flags = trip.original?.flags ?? 0
        if trip.originalRiverOutcome != nil { return "Crossing River" }
        if flags & 4 != 0 { return "Resting" }
        if flags & 2 == 0 { return "Stopped" }
        return flags & 8 != 0 ? "Delayed" : "Moving"
    }
    private var weatherFrame: Int {
        let trip = conditionsTrip
        return min(trip.gameEdition == .macintoshCD12 ? 10 : 9, max(0, trip.originalWeatherCategory))
    }
    /// CD weather10 has a separate resource; frame10 of15600 is the thermometer.
    static func weatherArtwork(edition: GameEdition, category: Int) -> (resource: Int, frame: Int) {
        if edition == .macintoshCD12 && category == 10 { return (20300, 0) }
        return (15600, min(9, max(0, category)))
    }
    private var weatherLines: [String] {
        let names = OriginalResources.strings(3012)
        guard names.count >= (weatherFrame + 1) * 2 else { return [conditionsTrip.weather.rawValue] }
        return Array(names[(weatherFrame * 2)...(weatherFrame * 2 + 1)]).filter { !$0.isEmpty }
    }
    private func text(_ value: String, x: Int, y: Int, width: Int, font: BitmapFont? = .plain12, alignment: Alignment = .leading) -> some View {
        OriginalText(text: value, font: font).frame(width: CGFloat(width), alignment: alignment).offset(x: CGFloat(x), y: CGFloat(y))
    }
    private func pair(_ key: String, _ value: String, y: Int, valueBold: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            text(key, x: 2, y: y, width: 115)
            text(value, x: 2, y: y, width: 115, font: valueBold ? .bold12 : .plain12, alignment: .trailing)
        }
    }
    @ViewBuilder private func icon(_ id: Int, _ label: String, row: Int, right: Bool = false, action: @escaping () -> Void) -> some View {
        if trip.gameEdition == .macintoshCD12 {
            Button(action: action) { Color.clear.frame(width: 52, height: 60) }
                .buttonStyle(CDSidebarButtonStyle(resource: id))
                .accessibilityLabel(label)
                .offset(x: right ? 442 : 0, y: CGFloat(row * 60))
        } else {
            Button(action: action) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        PixelArtwork(resource: 10129, monochromeResource: 129).frame(width: 42, height: 46)
                        PixelArtwork(resource: id, type: OriginalResources.iconType).frame(width: 32, height: 32)
                    }.frame(width: 42, height: 46).offset(x: 5, y: 2)
                }
                // The ribbon label is part of the sidebar artwork. Include it in
                // the same hit target instead of requiring a click on the picture.
                .frame(width: 52, height: 60, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(label).offset(x: right ? 442 : 0, y: CGFloat(row * 60))
        }
    }
    private func continueAction() {
        game.panel = nil
        if trip.phase == .river || trip.phase == .fork { game.showingRouteDecision = true }
        else { game.continueJourney() }
    }
}

/// CD pictures keep their authored dimensions (some extend beyond the pane).
/// The classic edition retains its original shared-strip frame selection.
private struct OriginalLandmarkArtwork: View {
    let trip: Journey
    let artwork: CDLandmarkPresentation.Artwork?

    private var index: Int { TrailCatalog.stops.firstIndex { $0.id == trip.locationID } ?? 0 }
    var body: some View {
        Group {
            if trip.gameEdition == .macintoshCD12 {
                if let art = artwork ?? CDLandmarkPresentation.artwork(index: index,
                    weather: trip.originalWeatherCategory, snow: Int(trip.original?.weather.snow ?? 0)) {
                    PixelArtwork(resource: art.colorResource, monochromeResource: art.monochromeResource,
                                 frame: art.frame, preserveDimensions: true)
                }
            } else {
                PixelArtwork(resource: trip.location.image, frame: trip.location.frame)
            }
        }.frame(width: 262, height: 155, alignment: .topLeading).clipped()
    }
}

private struct CDSidebarButtonStyle: ButtonStyle {
    let resource: Int
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        CDSidebarArtwork(resource: resource, pressed: configuration.isPressed, enabled: isEnabled)
            .contentShape(Rectangle())
    }
}

/// Preserve the wider ribbon hit target around the original42×46 control.
struct CDSidebarArtwork: View {
    let resource: Int
    var pressed = false
    var enabled = true
    var body: some View {
        CDIconControlArtwork(resource: resource, pressed: pressed, enabled: enabled)
            .offset(x: 5, y: 2)
            .frame(width: 52, height: 60, alignment: .topLeading)
    }
}

/// CODE4:0dd0 uses the full 262×199 illustrated event pane. The guide
/// corner comes from DITL6370's child rectangle and OffsetRect(5,-11).
struct CDNotificationPane: View {
    @ObservedObject var game: GameController
    let notice: CDNotificationRules.Selection
    var body: some View {
        let action = game.notificationAction()
        ZStack(alignment: .topLeading) {
            CDNotificationArtwork(art: notice.art, palette: game.notificationPalette)
                .frame(width: 262, height: 199)
            if notice.guide != 0 {
                PixelArtwork(resource: 6002, type: OriginalResources.iconType).frame(width: 32, height: 32)
                    .offset(x: 231, y: 167).allowsHitTesting(false)
            }
        }.frame(width: 262, height: 199).clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let point = value.location
                guard point.x >= 0, point.x < 262, point.y >= 0, point.y < 199 else { return }
                action(notice.guide != 0 && CDNotificationRules.opensGuide(x: point.x, y: point.y) ? .guide : .dismiss)
            })
            .accessibilityElement(children: .ignore).accessibilityLabel(game.notificationDescription ?? "Event notice")
            .accessibilityAddTraits(.isButton).accessibilityAction { action(.dismiss) }
            .accessibilityActions {
                if notice.guide != 0 { Button("Read about this event") { action(.guide) } }
            }
            .onChange(of: game.isOriginalModalPresented) { blocked in if !blocked { action(.redraw) } }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.modeDidChangeNotification)) { _ in action(.redraw) }
            #endif
    }
}

struct CDNotificationArtwork: View {
    let art: Int
    let palette: CDNotificationRules.PaletteCycle
    private static let images = SessionResourceCache<String, CGImage>()
    var body: some View {
        let resource = OriginalResources.resource(monochrome: 10200 + art, color: 20200 + art)
        let key = "\(OriginalResources.imageType):\(resource)"
        let source = Self.images.value(for: key, session: GameData.sessionID) {
            guard let entry = OriginalResources.manifest?.image(resource: resource, type: OriginalResources.imageType, frame: 0),
                  let url = GameData.resourceURL(entry.image_path),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let source {
            let image = OriginalResources.colorMode == .color256 ? (Self.recolored(source, palette: palette) ?? source) : source
            Image(decorative: image, scale: 1).resizable().interpolation(.none)
                .frame(width: CGFloat(image.width), height: CGFloat(image.height))
                .frame(width: 262, height: 199, alignment: .topLeading).clipped()
        }
    }

    /// Keep authored indices: RGB replacement would recolor unrelated entries
    /// that happen to have the same color. Monochrome/16-color bypass this path.
    static func recolored(_ image: CGImage, palette: CDNotificationRules.PaletteCycle) -> CGImage? {
        guard let original = image.colorSpace, original.model == .indexed,
              let base = original.baseColorSpace, base.numberOfComponents == 3,
              let source = original.colorTable, source.count == 256 * 3,
              let provider = image.dataProvider else { return nil }
        var colors = source
        for index in 207...225 {
            let from = palette.sourceIndex(for: index) * 3
            colors.replaceSubrange(index * 3..<index * 3 + 3, with: source[from..<from + 3])
        }
        guard let space = CGColorSpace(indexedBaseSpace: base, last: 255, colorTable: &colors) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: space,
            bitmapInfo: image.bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: image.renderingIntent)
    }
}
