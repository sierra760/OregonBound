import Foundation

struct TrailLeg: Equatable, Identifiable {
    let destination: String
    let miles: Int
    var id: String { destination }
}

struct TrailStop: Identifiable {
    let id: String
    let name: String
    let store: Bool
    let river: Bool
    let image: Int
    let frame: Int
    let guideTopic: String
    let talkTable: Int
    let routes: [TrailLeg]
}

enum TrailCatalog {
    // CODE 7 indexes A5-0x2887 with the landmark index (-1 for Independence).
    static func pricePercent(at id: String) -> Int {
        let percentages = [100, 100, 100, 125, 125, 150, 150, 150, 175, 175, 175, 200, 200, 225, 250, 250, 250, 250]
        return percentages[stops.firstIndex(where: { $0.id == id }) ?? 0]
    }

    // Route order and names follow STR# 3002. Distances and scenes are verified from
    // CODE16/CODE6 and initialized A5 tables; see docs/ORIGINAL_ROUTES.md.
    static let stops: [TrailStop] = [
        .init(id: "independence", name: "Independence, Missouri", store: true, river: false, image: 15300, frame: 0, guideTopic: "Independence, Missouri", talkTable: 3100, routes: [.init(destination: "kansas", miles: 102)]),
        .init(id: "kansas", name: "Kansas River Crossing", store: false, river: true, image: 15306, frame: 1, guideTopic: "Kansas River", talkTable: 3101, routes: [.init(destination: "big-blue", miles: 83)]),
        .init(id: "big-blue", name: "Big Blue River Crossing", store: false, river: true, image: 15306, frame: 1, guideTopic: "Big Blue River", talkTable: 3102, routes: [.init(destination: "kearney", miles: 119)]),
        .init(id: "kearney", name: "Fort Kearney", store: true, river: false, image: 15300, frame: 1, guideTopic: "Fort Kearney", talkTable: 3103, routes: [.init(destination: "chimney", miles: 250)]),
        .init(id: "chimney", name: "Chimney Rock", store: false, river: false, image: 15301, frame: 0, guideTopic: "Chimney Rock", talkTable: 3104, routes: [.init(destination: "laramie", miles: 86)]),
        .init(id: "laramie", name: "Fort Laramie", store: true, river: false, image: 15301, frame: 1, guideTopic: "Fort Laramie", talkTable: 3105, routes: [.init(destination: "rock", miles: 190)]),
        .init(id: "rock", name: "Independence Rock", store: false, river: false, image: 15302, frame: 0, guideTopic: "Independence Rock", talkTable: 3106, routes: [.init(destination: "south-pass", miles: 102)]),
        .init(id: "south-pass", name: "South Pass", store: false, river: false, image: 15302, frame: 1, guideTopic: "South Pass", talkTable: 3107, routes: [.init(destination: "bridger", miles: 57), .init(destination: "green", miles: 125)]),
        .init(id: "bridger", name: "Fort Bridger", store: true, river: false, image: 15303, frame: 0, guideTopic: "Fort Bridger", talkTable: 3108, routes: [.init(destination: "green", miles: 162)]),
        .init(id: "green", name: "Green River Crossing", store: false, river: true, image: 15306, frame: 1, guideTopic: "Green River", talkTable: 3109, routes: [.init(destination: "soda", miles: 144)]),
        .init(id: "soda", name: "Soda Springs", store: false, river: false, image: 15303, frame: 1, guideTopic: "Soda Springs", talkTable: 3110, routes: [.init(destination: "hall", miles: 57)]),
        .init(id: "hall", name: "Fort Hall", store: true, river: false, image: 15304, frame: 0, guideTopic: "Fort Hall", talkTable: 3111, routes: [.init(destination: "snake", miles: 182)]),
        .init(id: "snake", name: "Snake River Crossing", store: false, river: true, image: 15306, frame: 1, guideTopic: "Snake River", talkTable: 3112, routes: [.init(destination: "boise", miles: 114)]),
        .init(id: "boise", name: "Fort Boise", store: true, river: false, image: 15304, frame: 1, guideTopic: "Fort Boise", talkTable: 3113, routes: [.init(destination: "blue-mountains", miles: 160)]),
        .init(id: "blue-mountains", name: "Blue Mountains", store: false, river: false, image: 15305, frame: 0, guideTopic: "Blue Mountains", talkTable: 3114, routes: [.init(destination: "walla", miles: 55), .init(destination: "dalles", miles: 125)]),
        .init(id: "walla", name: "Fort Walla Walla", store: true, river: false, image: 15305, frame: 1, guideTopic: "Fort Walla Walla", talkTable: 3115, routes: [.init(destination: "dalles", miles: 120)]),
        .init(id: "dalles", name: "The Dalles", store: false, river: false, image: 15306, frame: 0, guideTopic: "Dalles, The", talkTable: 3116, routes: [.init(destination: "oregon", miles: 100)]),
        .init(id: "oregon", name: "Willamette Valley", store: false, river: false, image: 19090, frame: 0, guideTopic: "Willamette Valley", talkTable: 3117, routes: [])
    ]

    static func stop(_ id: String) -> TrailStop { stops.first { $0.id == id } ?? stops[0] }
    static func contains(_ id: String) -> Bool { stops.contains { $0.id == id } }
}
