import SwiftUI

struct OriginalMapArtwork: View {
    let trip: Journey
    private static let paths: [[OriginalMap.Delta]] = (128...135).map { id in
        guard let url = GameData.url(forResource: "hvof_\(id)", withExtension: "json", subdirectory: "map_viewports"),
              let data = try? Data(contentsOf: url),
              let path = try? JSONDecoder().decode(OriginalMap.PathResource.self, from: data) else { return [] }
        return path.points
    }
    private var points: [OriginalMap.Point] {
        let id = trip.phase == .travel ? trip.destinationID : trip.locationID
        let destination = (TrailCatalog.stops.firstIndex { $0.id == id } ?? 0) - 1
        var flags = 0
        if destination >= 8 && !trip.visited.contains("bridger") && trip.locationID != "bridger" { flags |= 1 }
        if destination >= 15 && !trip.visited.contains("walla") && trip.locationID != "walla" { flags |= 2 }
        if trip.phase == .rafting { flags |= 4 }
        return OriginalMap.paintedPoints(destination: destination, remaining: trip.phase == .travel ? trip.milesToNext : 0,
                                         miles: trip.miles, flags: flags, paths: Self.paths)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            PixelArtwork(resource: 15200)
            Canvas { context, _ in
                for point in points {
                    context.fill(Path(CGRect(x: point.x, y: point.y, width: 2, height: 2)), with: .color(.red))
                }
            }.allowsHitTesting(false)
        }.frame(width: 262, height: 119).accessibilityLabel("The Oregon Trail map")
    }
}
