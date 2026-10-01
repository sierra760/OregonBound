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
    private static var monochromeAtlas: CGImage? { load("system7_scrollbar_monochrome") }
    private static let monochromeTrack = TextureLoader.quickDrawPattern(rows: OriginalClassicScrollBarColors.trackPattern,
        width: 8, height: 8, originX: 0, originY: 0)
    static var thumb: CGImage? {
        // CDEF1:02e8 expands the thumb to16px before CopyBits. The final
        // control frame overwrites its two outside columns; retain the14px interior.
        if OriginalResources.colorMode == .monochrome {
            return monochromeAtlas?.cropping(to: CGRect(x: 8 * 16 + 1, y: 0, width: 14, height: 16))
        }
        return load("system7_scrollbar_thumb_rgb")
    }
    static var track: CGImage? {
        OriginalResources.colorMode == .monochrome ? monochromeTrack : load("system7_scrollbar_track_rgb")
    }
    static func arrow(down: Bool, pressed: Bool, enabled: Bool) -> CGImage? {
        if OriginalResources.colorMode == .monochrome {
            // CDEF1:048a–04ae uses the normal embedded arrow when disabled.
            let cell = (down ? 2 : 0) + (enabled && pressed ? 1 : 0)
            return monochromeAtlas?.cropping(to: CGRect(x: cell * 16, y: 0, width: 16, height: 16))
        }
        let cell = (down ? 3 : 0) + (enabled ? (pressed ? 1 : 0) : 2)
        return arrows?.cropping(to: CGRect(x: cell * 16, y: 0, width: 16, height: 16))
    }
}
