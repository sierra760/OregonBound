import SwiftUI
import SpriteKit

struct TrailView: View {
    @ObservedObject var game: GameController
    let trip: Journey

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Oregon Bound").font(.system(size: 16, weight: .bold, design: .serif))
                Spacer()
                Text(trip.dateText)
            }.padding(.horizontal, 10).frame(height: 28).background(Color.white)
            Rectangle().frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 6) {
                    control("Supplies", .supplies)
                    control("Map", .map)
                    control("Guide", .guide)
                    control("Talk", .talk)
                    control("Trade", .trade)
                    control("Rest", .rest)
                    control("Pace / Food", .conditions)
                    Button("Hunt") { game.perform { try JourneyEngine.beginHunt(&$0) } }.disabled(!trip.canHunt)
                    if trip.canShop { control("Buy", .shop) }
                    if trip.brokenPart != nil { Button("Repair") { game.perform { try JourneyEngine.repair(&$0) } } }
                }.frame(width: 64).padding(.top, 3)
                VStack(spacing: 6) {
                    TrailPicture(trip: trip, moving: game.running)
                        .id("\(trip.locationID)-\(trip.phase.rawValue)-\(trip.miles >= 900)")
                        .frame(width: 262, height: 155).border(.black)
                    Text(trip.phase == .travel ? "On the trail to \(trip.destination?.name ?? "Oregon")" : trip.location.name)
                        .font(.system(size: 12, weight: .bold, design: .serif)).multilineTextAlignment(.center).frame(height: 29)
                    journeyActions
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(trip.journal.suffix(3).reversed())) { entry in
                                Text(entry.text).font(.system(size: 11, design: .serif)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: .infinity).padding(5).background(Color.white).border(.black)
                }.frame(width: 262)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Conditions").bold()
                    value("Weather", trip.weather.rawValue)
                    value("Health", trip.healthLabel)
                    value("Pace", trip.pace.rawValue)
                    value("Rations", trip.rations.rawValue)
                    Divider()
                    value("Food", "\(trip.inventory[.food]) lbs")
                    value("Money", dollars(trip.cash))
                    value("Miles traveled", "\(trip.miles)")
                    if trip.phase == .travel { value("To next stop", "\(trip.milesToNext) mi") }
                    Spacer(minLength: 0)
                    Button("Party / Journal") { game.open(.journal) }
                }.font(.system(size: 11, design: .serif)).frame(width: 130, alignment: .leading)
            }.frame(height: 270).padding(7)
            Spacer(minLength: 0)
            HStack {
                Button("Main Menu") { game.mainMenu() }
                Button("Save") { game.running = false; game.persist() }
                Spacer()
                Text(game.running ? "Traveling…" : "Time out").font(.system(size: 10, design: .serif))
                Button(game.sound ? "Sound: On" : "Sound: Off") { game.sound.toggle() }
            }.padding(.horizontal, 8).frame(height: 30)
        }
    }

    private func control(_ title: String, _ panel: GamePanel) -> some View {
        Button(title) { game.open(panel) }.frame(maxWidth: .infinity)
    }
    private func value(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Text(title + ":").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).lineLimit(1).minimumScaleFactor(0.75).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var journeyActions: some View {
        if trip.phase == .river {
            VStack(spacing: 3) {
                Text("\(trip.riverWidth) feet wide • \(trip.riverDepth, specifier: "%.1f") feet deep").font(.system(size: 10))
                HStack(spacing: 4) {
                    ForEach(JourneyEngine.availableCrossings(in: trip)) { method in
                        Button(crossingLabel(method)) { game.perform { try JourneyEngine.cross(method, in: &$0) } }
                    }
                }
            }
        } else if trip.phase == .fork {
            if trip.locationID == "dalles" {
                HStack {
                    Button("Barlow Road ($10)") { game.perform { try JourneyEngine.takeBarlowRoad(&$0) } }
                    Button("Raft the Columbia") { game.perform { try JourneyEngine.beginRaft(&$0) } }
                }
            } else {
                HStack {
                    ForEach(trip.location.routes) { leg in
                        Button("\(TrailCatalog.stop(leg.destination).name) (\(leg.miles) mi)") { game.perform { try JourneyEngine.chooseRoute(leg.destination, in: &$0) } }
                    }
                }
            }
        } else if trip.phase == .outfitting {
            Button("Buy Supplies at Matt’s") { game.open(.shop) }
        } else {
            Button(game.running ? "Stop / Time Out" : "Continue on the Trail") { game.continueJourney() }.keyboardShortcut(.space, modifiers: [])
        }
    }

    private func crossingLabel(_ method: CrossingMethod) -> String {
        switch method { case .ford: return "Ford"; case .caulk: return "Caulk & float"; case .ferry: return "Ferry $5"; case .guide: return "Guide: 3 clothes" }
    }
}

struct TrailPicture: View {
    let trip: Journey
    let moving: Bool
    @State private var scene = TrailArtworkScene(size: CGSize(width: 262, height: 155))
    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 30)
            .onAppear { update() }
            .onChange(of: trip.locationID) { _ in update() }
            .onChange(of: trip.phase) { _ in update() }
            .onChange(of: moving) { _ in update() }
    }
    private func update() { scene.show(trip: trip, moving: moving) }
}

final class TrailArtworkScene: SKScene {
    func show(trip: Journey, moving: Bool) {
        removeAllChildren()
        scaleMode = .aspectFit
        backgroundColor = .white
        let imageID = trip.phase == .travel ? (trip.miles < 900 ? 15300 : 15305) : trip.location.image
        let frame = trip.phase == .travel ? (trip.miles < 900 ? 1 : 0) : trip.location.frame
        guard let entry = OriginalResources.manifest?.images(forResourceId: imageID).first(where: { $0.frame_index == frame }), let texture = TextureLoader.texture(for: entry) else { return }
        let art = SKSpriteNode(texture: texture)
        art.position = CGPoint(x: 131, y: 77.5)
        addChild(art)
        // Illustrations are independent pictures, never cycle through unrelated images.
        if moving {
            art.run(.repeatForever(.sequence([.moveBy(x: -1, y: 0, duration: 0.25), .moveBy(x: 1, y: 0, duration: 0.25)])))
        }
    }
}
