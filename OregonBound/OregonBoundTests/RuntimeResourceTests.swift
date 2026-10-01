import Foundation
import Testing
import SwiftUI
@testable import OregonBound

struct RuntimeResourceTests {
    #if os(macOS)
    @MainActor @Test func monochromePanePatternStaysAnchoredToItsPort() throws {
        for (left, top) in [(4,4), (5,4), (4,5)] {
            let renderer = ImageRenderer(content: ZStack(alignment: .topLeading) {
                Color.white
                OriginalPaneFrame(width: 8, height: 8, monochrome: true)
                    .offset(x: CGFloat(left), y: CGFloat(top))
            }.frame(width: 20, height: 20).coordinateSpace(name: OriginalWindowLayout.portSpace))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            for y in 0..<20 { for x in 0..<20 {
                let dx = x - left, dy = y - top
                let outer = (-2..<10).contains(dx) && (-2..<10).contains(dy)
                    && (dx == -2 || dx == 9 || dy == -2 || dy == 9)
                let inner = (-1..<9).contains(dx) && (-1..<9).contains(dy)
                    && (dx == -1 || dx == 8 || dy == -1 || dy == 8)
                let black = inner || (outer && (x+y).isMultiple(of: 2))
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                #expect(abs(color.redComponent - (black ? 0 : 1)) < 0.000001)
                #expect(abs(color.greenComponent - color.redComponent) < 0.000001)
                #expect(abs(color.blueComponent - color.redComponent) < 0.000001)
            }}
        }
    }
    @MainActor @Test func disabledIconLabelErasesAlternatePortPixelsWithoutGrayInk() throws {
        for left in [4, 5] {
            let renderer = ImageRenderer(content: ZStack(alignment: .topLeading) {
                Color.white
                Color.black.frame(width: 8, height: 6)
                    .overlay(CDDisabledControlTextPattern(paper: .white))
                    .offset(x: CGFloat(left), y: 4)
            }.frame(width: 18, height: 16).coordinateSpace(name: OriginalWindowLayout.portSpace))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            for y in 0..<16 { for x in 0..<18 {
                let inside = (left..<left+8).contains(x) && (4..<10).contains(y)
                let black = inside && !(x+y).isMultiple(of: 2)
                let color = try #require(bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
                #expect(abs(color.redComponent - (black ? 0 : 1)) < 0.000001)
            }}
        }
    }

    @MainActor @Test func monochromeSystemModalKeepsItsSolidOuterRingAndInactiveGrayBands() throws {
        for active in [true, false] {
            for left in [9, 10] {
                let top = 9
                let renderer = ImageRenderer(content: ZStack(alignment: .topLeading) {
                    Color.white
                    OriginalSystemModalFrame(contentWidth: 12, contentHeight: 6, active: active, monochrome: true) {
                        Color.white
                    }.offset(x: CGFloat(left), y: CGFloat(top))
                }.frame(width: 50, height: 42).coordinateSpace(name: OriginalWindowLayout.portSpace))
                renderer.scale = 1
                let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
                for y in 0..<42 { for x in 0..<50 {
                    let dx = x-left, dy = y-top
                    let distance = min(dx, dy, 27-dx, 21-dy)
                    let black = distance == 0 || ((distance == 3 || distance == 4) && (active || (x+y).isMultiple(of: 2)))
                    let color = try #require(bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
                    #expect(abs(color.redComponent - (black ? 0 : 1)) < 0.000001)
                    #expect(abs(color.greenComponent - color.redComponent) < 0.000001)
                    #expect(abs(color.blueComponent - color.redComponent) < 0.000001)
                }}
            }
        }
    }
    #endif

    @Test(arguments: Array(0..<18))
    func cdLandmarkFamiliesUseWeatherSnowAndSnakeException(index: Int) throws {
        for weather in [0, 1, 2, 10] {
            for snow in [0, 1, 65535] {
                let art = try #require(CDLandmarkPresentation.artwork(index: index, weather: weather, snow: snow))
                let variant = (weather > 1 ? 1 : 0) + (index != 12 && snow > 0 ? 2 : 0)
                #expect(art.monochromeResource == 5400 + 10 * index + variant)
                #expect(art.colorResource == 15400 + 10 * index + variant)
                #expect(art.frame == 0)
            }
        }
        #expect(CDLandmarkPresentation.artwork(index: -1, weather: 0, snow: 0) == nil)
        #expect(CDLandmarkPresentation.artwork(index: 18, weather: 0, snow: 0) == nil)
    }

    @Test func cdLandmarkRefreshesOnReopeningAndDisplayedWeatherOnly() {
        var pane = CDLandmarkPresentation()
        pane.update(index: 3, weather: 0, snow: 0, displayedWeather: 0, visible: true)
        #expect(pane.artwork?.colorResource == 15430)
        // A model change does not redraw the scene until Conditions draws it.
        pane.update(index: 3, weather: 2, snow: 1, displayedWeather: 0, visible: true)
        #expect(pane.artwork?.colorResource == 15430)
        pane.update(index: 3, weather: 2, snow: 1, displayedWeather: 2, visible: true)
        #expect(pane.artwork?.colorResource == 15433)
        // Snow alone does not recreate a visible pane.
        pane.update(index: 3, weather: 2, snow: 0, displayedWeather: 2, visible: true)
        #expect(pane.artwork?.colorResource == 15433)
        pane.update(index: 3, weather: 2, snow: 0, displayedWeather: 2, visible: false)
        pane.update(index: 3, weather: 2, snow: 0, displayedWeather: 2, visible: true)
        #expect(pane.artwork?.colorResource == 15431)
        // The source reopens on every category change, even within a variant.
        pane.update(index: 3, weather: 3, snow: 1, displayedWeather: 3, visible: true)
        #expect(pane.artwork?.colorResource == 15433)
        pane.update(index: 12, weather: 3, snow: 1, displayedWeather: 3, visible: true)
        #expect(pane.artwork?.colorResource == 15521)
    }

    @Test func extractsOnlySuppliedResourcesAndRejectsMissingInput() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destination) }
        // Thirteen synthetic scripts, each containing only the end opcode.
        let script = Data([0, 13] + Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 6, 2, 255), count: 13).flatMap { $0 })
        var cursor = Data(repeating: 0, count: 68)
        cursor[0] = 128
        cursor[32] = 192
        let fork = MacResourceFork(resources: [
            MacResource(type: "Scpt", id: 5310, name: nil, attributes: 0, data: script),
            MacResource(type: "CURS", id: 128, name: nil, attributes: 0, data: cursor)
        ])
        let output = ExtractionOutput(root: destination)
        try RuntimeResourceExtractor.extract(trailFork: fork, into: output)
        #expect(try Data(contentsOf: output.url("runtime/scpt_5310.bin")) == script)
        #expect(try Data(contentsOf: output.url("runtime/curs_128.bin")) == cursor)
        #expect(Array(OriginalHuntCursor.decode(cursor).prefix(12)) == [0,0,0,255,255,255,255,255,0,0,0,0])
        #expect(throws: RuntimeResourceExtractor.Failure.self) {
            try RuntimeResourceExtractor.extract(trailFork: MacResourceFork(resources: []), into: output)
        }
    }

    @Test(arguments: [5000, 5800, 5210])
    func iconLookupDoesNotSelectSameNumberedArtwork(id: Int) {
        func entry(_ type: String, _ frame: Int = 0) -> ManifestImage {
            ManifestImage(resource: ManifestResource(source_file: "synthetic", type: type,
                id: id, name: "", raw_length: 0), status: "decoded",
                image_path: "\(type)-\(id)-\(frame).png", width: 32, height: 32,
                mode: "RGBA", frame_index: frame, frame_count: 2, palette: nil)
        }
        for images in [[entry("Imag"), entry("cicn"), entry("Ima4"), entry("Imag", 1)],
                       [entry("cicn"), entry("Ima4"), entry("Imag"), entry("Imag", 1)]] {
            let manifest = GraphicsManifest(source_file: "synthetic", images: images)
            #expect(manifest.image(resource: id, type: "cicn")?.image_path == "cicn-\(id)-0.png")
            #expect(manifest.image(resource: id, type: "Ima4")?.image_path == "Ima4-\(id)-0.png")
            #expect(manifest.image(resource: id, type: "Imag", frame: 1)?.image_path == "Imag-\(id)-1.png")
            #expect(manifest.image(resource: id, type: "cicn", frame: 1) == nil)
            #expect(manifest.image(resource: id, type: "ICON") == nil)
            #expect(manifest.image(resource: id)?.image_path == images[0].image_path)
            #expect(manifest.image(resource: id + 1, type: "cicn") == nil)
        }
    }

    @Test func dustStormArtworkIsNotTheThermometerOrHail() {
        let dust = OriginalTrailView.weatherArtwork(edition: .macintoshCD12, category: 10)
        #expect(dust.resource == 20300 && dust.frame == 0)
        for category in 0...9 {
            let cd = OriginalTrailView.weatherArtwork(edition: .macintoshCD12, category: category)
            let classic = OriginalTrailView.weatherArtwork(edition: .macintosh11, category: category)
            #expect(cd.resource == 15600 && cd.frame == category)
            #expect(classic == cd)
        }
        #expect(OriginalJournalRules.weatherEvent(13, edition: .macintoshCD12) == "Dust Storm.")
        #expect(OriginalJournalRules.weatherEvent(13) == nil)
    }

    @Test func cdConditionsRedrawsOnPublishedRevisionsAndPreservesSnapshots() {
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.inventory[.food] = 100
        var state = CDConditionsPresentation()
        state.show(trip)
        #expect(state.revision == 1 && !state.warningPhase)
        let poll1 = state.poll()
        #expect(poll1 && state.warningPhase)
        let poll2 = state.poll()
        #expect(!poll2 && state.warningPhase)
        trip.inventory[.food] = 101
        #expect(state.snapshot?.totalFood == 100)
        state.publish(trip)
        #expect(state.snapshot?.totalFood == 101)
        let poll3 = state.poll()
        #expect(poll3 && !state.warningPhase)
        #expect(trip.randomState == 7)
    }

    @Test func cdConditionsHiddenAndBlockedPollsHaveDifferentRevisionSemantics() {
        let trip = Journey(seed: 7, edition: .macintoshCD12)
        var state = CDConditionsPresentation()
        state.show(trip)
        state.hide()
        let poll4 = state.poll()
        #expect(!poll4) // consumes revision without drawing
        #expect(!state.warningPhase)
        state.show(trip)
        #expect(state.warningPhase) // full reveal draw
        let poll5 = state.poll()
        #expect(!poll5)
        state.publish(trip)
        let poll6 = state.poll(active: false)
        #expect(!poll6)
        let poll7 = state.poll(modalBlocked: true)
        #expect(!poll7)
        #expect(state.warningPhase)
        let poll8 = state.poll()
        #expect(poll8 && !state.warningPhase)
        let replacement = Journey(seed: 8, edition: .macintoshCD12)
        state.show(replacement)
        #expect(state.revision == 3 && state.warningPhase)
        #expect(state.snapshot?.id == replacement.id)
    }

    @Test func cdConditionsPreservesSourceByteVersusLongComparisonAfter255() {
        let trip = Journey(seed: 7, edition: .macintoshCD12)
        var state = CDConditionsPresentation()
        state.show(trip)
        for _ in 1..<255 { state.publish(trip) }
        #expect(state.revision == 255)
        let poll9 = state.poll()
        #expect(poll9)
        let poll10 = state.poll()
        #expect(!poll10)
        state.publish(trip)
        #expect(state.revision == 256)
        let poll11 = state.poll()
        #expect(poll11)
        let phase = state.warningPhase
        let poll12 = state.poll()
        #expect(poll12 && state.warningPhase != phase)
    }

    @Test func cdConditionsWarningThresholdsAndOppositeWagonPhase() {
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.inventory[.food] = 100
        trip.original?.badness = 105
        trip.original?.cdWagonWeight = 2750
        trip.original?.flags = 4
        let warning = CDConditionsPresentation.styles(for: trip, warningPhase: true)
        #expect(warning.food && warning.health && warning.weight && !warning.wagon)
        let opposite = CDConditionsPresentation.styles(for: trip, warningPhase: false)
        #expect(!opposite.food && !opposite.health && !opposite.weight && opposite.wagon)
        trip.inventory.perishableFood = 1
        trip.original?.badness = 104
        trip.original?.cdWagonWeight = 2749
        let safe = CDConditionsPresentation.styles(for: trip, warningPhase: true)
        #expect(!safe.food && !safe.health && !safe.weight)
        for (flags, status, flashes) in [(0,"Stopped",false),(2,"Moving",false),(8,"Stopped",false),(10,"Delayed",true),(14,"Resting",true)] {
            trip.original?.flags = UInt8(flags)
            #expect(CDConditionsPresentation.wagonStatus(for: trip) == status)
            #expect(CDConditionsPresentation.styles(for: trip, warningPhase: false).wagon == flashes)
        }
        trip.originalRiverOutcome = .init(requestedMethodRaw: 1, animationMethodRaw: 1,
            failureKind: 0, status: 0, currentFactor: 0, phase: .animation)
        #expect(CDConditionsPresentation.wagonStatus(for: trip) == "Crossing River")
        #expect(!CDConditionsPresentation.styles(for: trip, warningPhase: false).wagon)
    }

    @MainActor private func conditionsController(_ root: URL, edition: GameEdition = .macintoshCD12) throws -> GameController {
        let store = JourneyStore(directory: root, edition: edition)
        try store.savePreferences(.init())
        return GameController(store: store,
            random: OriginalRandomStream(seed: 7),
            audio: GameAudio(playback: OriginalAudioBackendTests.Output(), scheduleIdle: { _ in }))
    }

    @MainActor @Test func cdConditionsControllerPublishesStoppedWorldWithoutAdvancingTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = try conditionsController(root)
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.phase = .landmark; trip.inventory[.food] = 100
        game.trip = trip
        game.showConditions()
        game.pollConditions()
        let revision = game.cdConditions.revision
        game.perform { $0.inventory[.food] = 99 }
        #expect(game.cdConditions.revision == revision)
        game.tick()
        #expect(game.error == nil)
        #expect(game.cdConditions.revision == revision + 1)
        #expect(game.trip?.daysElapsed == trip.daysElapsed && game.random.seed == 7)
        #expect(game.cdConditions.snapshot?.inventory[.food] == 99)
        #expect(game.cdConditions.displayedSnapshot?.inventory[.food] == 100)
        #expect(game.cdConditions.snapshot?.original?.cdWagonWeight == game.trip?.inventory.cdWagonWeight)
        game.pollConditions()
        #expect(game.cdConditions.displayedSnapshot?.inventory[.food] == 99)
    }

    @MainActor @Test func cdConditionsDailyPulsePublishesOnceAndBlockedDispatchFreezes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = try conditionsController(root)
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.phase = .landmark; trip.inventory[.food] = 1000
        trip.original?.weather.initialized = true; trip.original?.weather.category = 0x8a
        try JourneyEngine.beginRest(days: 2, in: &trip)
        game.trip = trip; game.showConditions()
        let revision = game.cdConditions.revision
        for _ in 0..<Int(trip.timing.timerThreshold) { game.tick() }
        #expect(game.trip?.daysElapsed == trip.daysElapsed + 1)
        #expect(game.cdConditions.revision == revision + UInt32(trip.timing.timerThreshold))
        #expect(game.cdConditions.snapshot?.daysElapsed == trip.daysElapsed + 1)
        #expect(game.cdConditions.displayedSnapshot?.daysElapsed == trip.daysElapsed)
        let phase = game.cdConditions.warningPhase
        let stoppedRevision = game.cdConditions.revision
        game.applicationActive = false; game.tick(); game.pollConditions()
        #expect(game.cdConditions.revision == stoppedRevision && game.cdConditions.warningPhase == phase)
        game.applicationActive = true; game.showingAbout = true
        game.tick(); game.pollConditions()
        #expect(game.cdConditions.revision == stoppedRevision && game.cdConditions.warningPhase == phase)
        game.showingAbout = false; game.pollConditions()
        #expect(game.cdConditions.displayedSnapshot?.daysElapsed == trip.daysElapsed + 1)
    }

    @MainActor @Test func cdConditionsVisibilityReloadAndClassicIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = try conditionsController(root)
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.phase = .landmark; trip.inventory[.food] = 100
        game.trip = trip; game.showConditions(); game.setConditionsVisible(false)
        game.tick(); game.pollConditions()
        #expect(!game.cdConditions.warningPhase && !game.cdConditions.isVisible)
        game.setConditionsVisible(true)
        #expect(game.cdConditions.warningPhase)
        let revision = game.cdConditions.revision
        trip.inventory[.food] = 150
        try game.store.save(trip)
        game.resume()
        #expect(game.error == nil)
        #expect(game.cdConditions.revision == revision + 1)
        #expect(game.cdConditions.displayedSnapshot?.totalFood == 150)
        #expect(!game.cdConditions.warningPhase)
        let classic = try conditionsController(root, edition: .macintosh11)
        classic.trip = Journey(seed: 7); classic.trip?.phase = .landmark
        classic.showConditions(); classic.tick(); classic.pollConditions()
        #expect(classic.cdConditions.snapshot == nil && classic.cdConditions.revision == 0)
    }

    @MainActor @Test func cdConditionsTerminalPacketsDoNotAdvanceCounterAcrossJourneys() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = try conditionsController(root)
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        trip.phase = .landmark
        trip.inventory[.food] = 1000; trip.inventory[.oxen] = 8
        trip.original?.weather.initialized = true; trip.original?.weather.category = 0x8a
        game.trip = trip; game.showConditions()
        for _ in 0..<252 { game.tick() }
        #expect(game.cdConditions.revision == 253)
        game.trip?.phase = .travel; game.trip?.locationID = "dalles"
        game.trip?.destinationID = "oregon"; game.trip?.legDistance = 100
        game.trip?.legProgress = 99; game.trip?.original?.flags = 10
        game.trip?.delayDays = 0 // The expired delay flag suppresses events, then clears before movement.
        // The stopped counter is already one pulse short of a daily update.
        game.tick()
        #expect(game.trip?.won == true && game.trip?.phase == .finished)
        #expect(game.cdConditions.revision == 253) // Terminal receiver bypasses the revision increment.
        #expect(game.cdConditions.snapshot?.won == true)
        game.setConditionsVisible(false); game.pollConditions()
        var next = Journey(seed: 9, edition: .macintoshCD12); next.phase = .landmark
        game.trip = next; game.setConditionsVisible(true)
        #expect(game.cdConditions.revision == 254)
        game.pollConditions()
        let phase = game.cdConditions.warningPhase
        game.pollConditions()
        #expect(game.cdConditions.warningPhase == phase)
        game.tick(); game.tick()
        #expect(game.cdConditions.revision == 256)
        game.pollConditions()
        let overflowPhase = game.cdConditions.warningPhase
        game.pollConditions()
        #expect(game.cdConditions.warningPhase != overflowPhase)
        game.perform { JourneyEngine.finish(&$0, won: false, reason: "Test loss") }
        #expect(game.cdConditions.revision == 256) // Loss has no arrival publication.
    }

    @Test func cdConditionsInactiveTerminalWorldDoesNotRedrawAfterCounterOverflow() {
        var state = CDConditionsPresentation()
        var trip = Journey(seed: 7, edition: .macintoshCD12)
        state.show(trip)
        for _ in 0..<255 { state.publish(trip) }
        state.poll()
        let phase = state.warningPhase
        JourneyEngine.finish(&trip, won: true, reason: "Test arrival")
        state.publish(trip); state.publish(trip)
        #expect(state.revision == 256)
        let redrawn = state.poll()
        #expect(!redrawn && state.warningPhase == phase)
    }

    @Test func aboutIdentifiesTheIndependentApp() {
        #expect(OriginalAboutRules.program == "Oregon Bound")
        #expect(OriginalAboutRules.copyright == "Copyright 2026 Sierra Burkhart")
        #expect(OriginalAboutRules.State().heading == "Original game team:")
        #expect(OriginalAboutRules.attribution.contains("Not affiliated or endorsed."))
    }
}
