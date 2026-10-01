import Foundation

/// CODE7:141e–155c chooses a separate image for each CD landmark and season.
/// CODE4:2908–2952 recreates an existing pane when Conditions draws a changed
/// weather category. Snow accumulation alone does not refresh an open pane.
struct CDLandmarkPresentation {
    struct Artwork: Equatable {
        let monochromeResource: Int
        let colorResource: Int
        // The old scene table supplies a frame, but each CD image has one frame;
        // the source image loader clamps that requested frame to zero.
        let frame = 0
    }
    private(set) var artwork: Artwork?
    private var index: Int?
    private var displayedWeather: Int?
    private var visible = false

    static func artwork(index: Int, weather: Int, snow: Int) -> Artwork? {
        guard (0..<18).contains(index) else { return nil }
        let variant = (weather > 1 ? 1 : 0) + (index != 12 && snow > 0 ? 2 : 0)
        return Artwork(monochromeResource: 5400 + index * 10 + variant,
                       colorResource: 15400 + index * 10 + variant)
    }

    mutating func update(index: Int, weather: Int, snow: Int, displayedWeather: Int, visible: Bool) {
        if visible && (!self.visible || self.index != index || self.displayedWeather != displayedWeather) {
            artwork = Self.artwork(index: index, weather: weather, snow: snow)
        }
        self.index = index
        self.displayedWeather = displayedWeather
        self.visible = visible
    }
}
