import SwiftUI

struct PanelView: View {
    @ObservedObject var game: GameController
    let panel: GamePanel
    @State private var restDays = 3
    @State private var give: Supply = .bullets
    @State private var receive: Supply = .food
    @State private var tradeQuantity = 20
    @State private var topic = 0
    @State private var talkIndex = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(panel.rawValue).font(.system(size: 17, weight: .bold, design: .serif))
                Spacer()
                Button("Close") { game.panel = nil }.keyboardShortcut(.cancelAction)
            }
            Divider()
            if let trip = game.trip { tripPanel(trip) }
            else if panel == .scores { scoreList }
            else { help }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func tripPanel(_ trip: Journey) -> some View {
        switch panel {
        case .shop: ScrollView { ShopView(game: game, trip: trip) }
        case .supplies:
            Text("Money: \(dollars(trip.cash))").bold()
            ForEach(Supply.allCases) { item in
                HStack { Text(item == .food && trip.gameEdition == .macintoshCD12 ? "Non-perishable food" : item.title); Spacer(); Text("\(trip.displayQuantity(item))") }.padding(.horizontal, 35)
            }
            if trip.gameEdition == .macintoshCD12 {
                HStack { Text("Perishable food"); Spacer(); Text("\(trip.inventory.perishableFood)") }.padding(.horizontal, 35)
            }
            Text("\(trip.livingMembers.count) of \(trip.members.count) people are alive. Health: \(trip.healthLabel).")
        case .map:
            PixelArtwork(resource: 15200, monochromeResource: 5200).frame(height: 155)
            Text("\(trip.miles) miles traveled • \(trip.location.name)").bold()
            if trip.phase == .travel { Text("Next: \(trip.destination?.name ?? "Oregon") in \(trip.milesToNext) miles") }
            ScrollView(.horizontal) { HStack { ForEach(trip.visited, id: \.self) { Text(TrailCatalog.stop($0).name).font(.system(size: 10)).padding(4).background(.white) } } }
        case .guide:
            Picker("Topic", selection: $topic) { ForEach(OriginalResources.guide) { Text($0.title).tag($0.id) } }
            ScrollView { Text(OriginalResources.guide.first(where: { $0.id == topic })?.text ?? "The guidebook could not be loaded.").frame(maxWidth: .infinity, alignment: .leading).lineSpacing(3) }
                .onAppear { topic = OriginalResources.guide.first(where: { $0.title == trip.location.guideTopic })?.id ?? 0 }
        case .talk:
            let quotes = OriginalResources.strings(trip.location.talkTable).filter { $0.count > 20 }
            Text("A traveler near \(trip.location.name) tells you:").bold()
            ScrollView { Text(quotes.isEmpty ? "Keep a close watch on your supplies and the weather." : quotes[talkIndex % quotes.count]).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading) }
            Button("Talk to Someone Else") { talkIndex += 1 }
        case .trade:
            Text("A traveler will exchange supplies with you. Trading takes one day.").fixedSize(horizontal: false, vertical: true)
            Picker("Give", selection: $give) { ForEach(Supply.allCases) { Text($0.title).tag($0) } }
            Stepper("Quantity: \(tradeQuantity) (you have \(trip.displayQuantity(give)))", value: $tradeQuantity, in: 1...2000)
            Picker("Receive", selection: $receive) { ForEach(Supply.allCases) { Text($0.title).tag($0) } }
            Text("Offer: \(tradeQuantity * give.unitPrice * 3 / (receive.unitPrice * 4)) \(receive.title.lowercased())")
            Button("Accept Trade") { game.perform { try JourneyEngine.trade(give: give, quantity: tradeQuantity, receive: receive, in: &$0) } }
                .disabled(give == receive || tradeQuantity > trip.displayQuantity(give))
        case .rest:
            Text("Resting helps your party recover, but you still need food each day. At a river, you can wait for the water to fall.").fixedSize(horizontal: false, vertical: true)
            Stepper("Rest for \(restDays) days", value: $restDays, in: 1...9)
            Button("Rest") { game.perform { try JourneyEngine.rest(days: restDays, in: &$0) }; game.panel = nil }
        case .conditions, .pace, .rations:
            Picker("Pace", selection: Binding(get: { trip.pace }, set: { pace in game.perform { $0.pace = pace } })) { ForEach(Pace.allCases) { Text($0.rawValue).tag($0) } }
            Text("A faster pace covers more miles but wears down your party.")
            Picker("Food rations", selection: Binding(get: { trip.rations }, set: { rations in game.perform { $0.rations = rations } })) { ForEach(Rations.allCases) { Text($0.rawValue).tag($0) } }
            Text("Filling: 3 pounds per person per day. Meager: 2 pounds. Bare bones: 1 pound. Less food weakens your party.")
        case .journal:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) { ForEach(trip.members) { member in VStack(alignment: .leading) { Text(member.name).bold(); Text(member.condition) } } }.frame(width: 110)
                ScrollView { VStack(alignment: .leading, spacing: 9) { ForEach(trip.journal.reversed()) { entry in Text("Day \(entry.day + 1): \(entry.text)").frame(maxWidth: .infinity, alignment: .leading) } } }
            }
        case .scores: scoreList
        case .help: help
        }
    }

    private var scoreList: some View {
        VStack(spacing: 7) {
            if game.scores.isEmpty { Text("No travelers have reached Oregon yet.") }
            ForEach(Array(game.scores.enumerated()), id: \.element.id) { rank, score in
                HStack { Text("\(rank + 1).").frame(width: 20); Text(score.name).bold(); Text(score.profession.rawValue).foregroundStyle(.secondary); Spacer(); Text("\(score.score)") }
            }
        }
    }

    private var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lead your wagon from Independence to Oregon in 1848. Name your party, choose an occupation, and buy oxen, food, clothing, ammunition, and spare parts.")
                Text("Continue advances the journey. Stop pauses it. Travel also pauses at events and landmarks. Use the trail controls to rest, hunt, trade, change pace or rations, and check your party’s health.")
                Text("Hunting: click or tap a moving animal to fire. Each shot uses a bullet; you can carry 100 pounds back. The hunt lasts 30 seconds. Leave Hunt ends it early.")
                Text("Rafting: move with the left/right arrows, click, or drag across the river. Avoid rocks and stay afloat for 60 seconds to reach the landing. Ten collisions sink the raft.")
                Text("Your progress is saved after each action. Resume restores the latest save. Minigames save when they end; closing during a minigame returns you to the previous trail save.")
            }.lineSpacing(2)
        }
    }
}

struct ShopView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    @State private var quantities: [Supply: Int] = [:]
    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .top, spacing: 12) {
                PixelArtwork(resource: 16080, monochromeResource: 6080).frame(width: 100, height: 95)
                VStack(spacing: 6) {
                    Text(trip.locationID == "independence" ? "Matt’s General Store" : "\(trip.location.name) Store").bold()
                    Text("You have \(dollars(trip.cash))")
                    Text("Matt recommends six oxen, 200 pounds of food and two sets of clothing for each person, bullets, and spare wagon parts.").font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(height: 95)
            ForEach(Supply.allCases) { item in
                HStack(spacing: 5) {
                    Text(item.title).frame(width: 115, alignment: .leading)
                    Text("Have \(trip.displayQuantity(item))").frame(width: 58, alignment: .trailing)
                    let amount = quantities[item] ?? item.packSize
                    Stepper("\(amount)", value: Binding(get: { quantities[item] ?? item.packSize }, set: { quantities[item] = $0 }), in: item.packSize...item.purchaseCapacity, step: item.packSize).frame(width: 77)
                    Button("Buy \(dollars(JourneyEngine.price(item, quantity: amount, in: trip)))") { game.perform { try JourneyEngine.buy(item, quantity: amount, in: &$0) } }.frame(width: 105)
                }.font(.system(size: 10, design: .serif))
            }
            if trip.phase == .outfitting {
                Button("Start the Journey") { game.perform { try JourneyEngine.depart(&$0) } }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct EndingView: View {
    @ObservedObject var game: GameController
    let trip: Journey
    var body: some View {
        VStack(spacing: 8) {
            if trip.won { PixelArtwork(resource: 19090, monochromeResource: 9090).frame(height: 150) }
            else { Text("Your journey has ended").font(.system(size: 26, weight: .bold, design: .serif)).padding(.top, 25) }
            Text(trip.finishReason).bold().multilineTextAlignment(.center)
            if trip.won {
                HStack(alignment: .top, spacing: 35) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(JourneyEngine.scoreLines(trip)) { line in HStack { Text(line.id); Spacer(); Text("\(line.points)") } }
                    }.frame(width: 200).font(.system(size: 10))
                    VStack(spacing: 8) {
                        Text("Your Score").bold()
                        Text("\(JourneyEngine.score(trip))").font(.system(size: 28, weight: .bold, design: .serif))
                        Text("Occupation ×\(trip.profession.scoreMultiplierText)").font(.system(size: 9))
                    }
                }
            } else {
                Text("\(trip.miles) miles in \(trip.daysElapsed) days").padding()
                Text("\(trip.livingMembers.count) of \(trip.members.count) travelers survived.")
            }
            Spacer(minLength: 0)
            HStack {
                Button("Hall of Fame") { game.open(.scores) }
                Button("New Game") { game.trip = nil; game.creatingGame = true }
                Button("Main Menu") { game.mainMenu() }
            }
        }.padding(12)
    }
}
