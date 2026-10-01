import SwiftUI

/// Requested System7 control RGB, before an indexed guest device's CLUT mapping.
/// These source-derived parts are distinct from a verified emulator pixel capture.
enum OriginalScrollbarArtwork {
    private static let cache = SessionResourceCache<String, CGImage>()
    private static func load(_ name: String) -> CGImage? {
        cache.value(for: name, session: GameData.sessionID) { uncachedLoad(name) }
    }
    private static func uncachedLoad(_ name: String) -> CGImage? {
        guard let url = GameData.url(forResource: name, withExtension: "png", subdirectory: "system_controls"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
    private static var arrows: CGImage? { load("system7_scrollbar_arrows_system") }
    static var thumb: CGImage? { load("system7_scrollbar_thumb_rgb") }
    static var track: CGImage? { load("system7_scrollbar_track_rgb") }
    static func arrow(down: Bool, pressed: Bool, enabled: Bool) -> CGImage? {
        let cell = (down ? 3 : 0) + (enabled ? (pressed ? 1 : 0) : 2)
        return arrows?.cropping(to: CGRect(x: cell * 16, y: 0, width: 16, height: 16))
    }
}
