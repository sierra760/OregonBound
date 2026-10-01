import Foundation
import Testing
@testable import OregonBound

struct RuntimeResourceTests {
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

    @Test func aboutIdentifiesTheIndependentApp() {
        #expect(OriginalAboutRules.program == "Oregon Bound")
        #expect(OriginalAboutRules.copyright == "Copyright 2026 Sierra Burkhart")
        #expect(OriginalAboutRules.State().heading == "Original game team:")
        #expect(OriginalAboutRules.attribution.contains("Not affiliated or endorsed."))
    }
}
