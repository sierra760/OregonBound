import SpriteKit
import OSLog
import ImageIO
import QuartzCore
import CryptoKit

private let textureLogger = Logger(subsystem: "com.sierraburkhart.OregonBound", category: "TextureLoader")

enum TextureLoader {
    private static let cache = NSCache<NSString, SKTexture>()

    /// QuickDraw qd.gray is an opaque AA55 pattern anchored to the drawing
    /// port, not the rectangle being painted. Set bits use black ink.
    static func quickDrawGray(width: Int, height: Int, originX: Int, originY: Int) -> CGImage? {
        quickDrawPattern(rows: [0xaa,0x55,0xaa,0x55,0xaa,0x55,0xaa,0x55],
                         width: width, height: height, originX: originX, originY: originY)
    }

    /// QuickDraw's eight-row, most-significant-bit-first patterns repeat in port coordinates.
    static func quickDrawPattern(rows: [UInt8], width: Int, height: Int, originX: Int, originY: Int) -> CGImage? {
        guard rows.count == 8, width > 0, height > 0, width <= 16384, height <= 16384,
              width * height <= 16 * 1024 * 1024 else { return nil }
        let phaseX = originX & 7, phaseY = originY & 7
        var pixels = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width where rows[(y + phaseY) & 7] & (0x80 >> ((x + phaseX) & 7)) != 0 {
                pixels[y * width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Classic QuickDraw animal sprites use white as their transparent color key.
    /// Core Graphics color masks cannot be applied to an image that already has alpha.
    static func removingWhiteBackground(from source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[offset] == 255 && pixels[offset + 1] == 255 && pixels[offset + 2] == 255 {
                pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// SpriteKit uploads channel values without applying the image's ICC profile.
    /// Match those values to the actual output layer, rather than assuming a P3 display.
    static func renderingColorSpace(for view: SKView?) -> CGColorSpace {
        #if os(macOS)
        if let space = (view?.layer as? CAMetalLayer)?.colorspace { return space }
        if let space = view?.window?.screen?.colorSpace?.cgColorSpace { return space }
        #else
        if let view, let space = (view.layer as? CAMetalLayer)?.colorspace { return space }
        #endif
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static func renderingColorSpaceID(for view: SKView?) -> String {
        let space = renderingColorSpace(for: view)
        if let data = space.copyICCData() {
            return SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
        }
        return (space.name as String?) ?? "sRGB"
    }

    /// Also refresh paused artwork when a Mac window moves between displays.
    static func observeRenderingColorSpace(in view: SKView, changed: @escaping () -> Void) -> [NSObjectProtocol] {
        #if os(macOS)
        let names: [Notification.Name] = [NSWindow.didChangeScreenNotification, NSWindow.didChangeBackingPropertiesNotification]
        return names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak view] note in
                guard let view, let window = note.object as? NSWindow, window === view.window else { return }
                changed()
            }
        }
        #else
        let names: [Notification.Name] = [UIScreen.modeDidChangeNotification, UIScene.didActivateNotification]
        return names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak view] _ in
                guard view?.window != nil else { return }
                changed()
            }
        }
        #endif
    }

    /// The resource palette is sRGB, including PNGs whose indexed base is DeviceRGB.
    /// Tag the original samples first; conversion must never edit their palette indices.
    static func convertedImage(_ source: CGImage, to destination: CGColorSpace) -> CGImage? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let tagged: CGImage
        if let space = source.colorSpace, space.model == .indexed, var table = space.colorTable {
            guard let indexed = CGColorSpace(indexedBaseSpace: sRGB, last: table.count / 3 - 1,
                                             colorTable: &table),
                  let copy = source.copy(colorSpace: indexed) else { return nil }
            tagged = copy
        } else if source.colorSpace?.model == .monochrome {
            // A one-component bitmap cannot be retagged with a three-component
            // RGB space. Draw its original black/white samples into the RGBA
            // destination instead; river and hunt masks need that conversion.
            tagged = source
        } else {
            guard let copy = source.copy(colorSpace: sRGB) else { return nil }
            tagged = copy
        }
        guard let context = CGContext(data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: destination,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(tagged, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()
    }

    static func texture(cgImage source: CGImage, renderingIn view: SKView?) -> SKTexture {
        let texture: SKTexture
        if let image = convertedImage(source, to: renderingColorSpace(for: view)),
           let data = image.dataProvider?.data {
            // Upload the converted RGBA samples directly. SpriteKit's CGImage
            // path can lose the final transparent pixel with a display ICC profile.
            texture = SKTexture(data: data as Data,size: CGSize(width: image.width,height: image.height),flipped: true)
        } else {
            texture = SKTexture(cgImage: source)
        }
        texture.filteringMode = .nearest
        return texture
    }

    static func texture(for image: ManifestImage, renderingIn view: SKView? = nil) -> SKTexture? {
        guard let resourceURL = GameData.resourceURL(image.image_path) else { return nil }
        // A texture converted for one monitor must never be reused on another profile.
        let key = "\(GameData.sessionID.uuidString):\(resourceURL.path):\(renderingColorSpaceID(for: view))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(resourceURL as CFURL, nil),
              let imageSource = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            textureLogger.error("TextureLoader: image load failed — \(resourceURL.path, privacy: .public)")
            return nil
        }
        let texture = texture(cgImage: imageSource, renderingIn: view)
        cache.setObject(texture, forKey: key)
        return texture
    }

    static func textures(for images: [ManifestImage], renderingIn view: SKView? = nil) -> [SKTexture] {
        images.compactMap { texture(for: $0, renderingIn: view) }
    }
}
