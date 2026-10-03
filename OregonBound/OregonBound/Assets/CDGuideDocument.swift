import Foundation
import CoreGraphics
import CoreText

/// On-demand presentation of the imported document. Only a few page images are
/// retained; neither browsing nor captions need to render the entire manual.
final class CDGuideDocument {
    struct Picture {
        let frame: QuickDrawRect
        let image: CGImage
        let visibleText: CDGuideText?
        let transcript: CDGuideText.Transcript
        var paperOrigin: CDUserGuideRules.Point {
            .init(x: (612 - image.width) / 2, y: 0)
        }
        func text(in crop: QuickDrawRect? = nil) -> String {
            visibleText?.text(in: crop) ?? transcript.text(in: crop)
        }
        func linkText(in bounds: CDUserGuide.Rect) -> String {
            text(in: .init(top: bounds.top, left: bounds.left - paperOrigin.x,
                           bottom: bounds.bottom, right: bounds.right - paperOrigin.x))
        }
    }
    struct Caption { let image: CGImage; let text: String }

    let guide: CDUserGuide
    let usesOriginalFonts: Bool
    private let fonts: [CDGuideFonts.Key: CDGuideRaster.Font]
    private var cache: [Int: Picture] = [:]
    private var order: [Int] = []
    static let maximumCachedImageBytes = 16 * 1024 * 1024
    private(set) var cachedImageBytes = 0

    init(guide: CDUserGuide, originalFonts: CDGuideFonts?) throws {
        self.guide = guide
        usesOriginalFonts = originalFonts != nil
        fonts = try originalFonts.map(CDGuideDrawing.fonts) ?? CDGuideDrawing.substituteFonts()
    }

    func picture(_ id: Int) throws -> Picture {
        if let existing = cache[id] {
            order.removeAll { $0 == id }; order.append(id)
            return existing
        }
        guard let bytes = guide.pictures[id] else { throw CDUserGuide.Failure.invalid("missing guide picture") }
        let picture = try CDGuidePicture(data: bytes)
        let font: (Int, Int) -> CDGuideRaster.Font? = { self.fonts[.init(family: $0, size: $1)] }
        let raster = try CDGuideRaster.render(picture, fonts: font)
        guard let provider = CGDataProvider(data: Data(raster.pixels) as CFData),
              let image = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: raster.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CDUserGuide.Failure.invalid("unable to display guide picture")
        }
        let result = Picture(frame: picture.frame, image: image,
            visibleText: usesOriginalFonts ? try CDGuideText(picture: picture, fonts: font) : nil,
            transcript: CDGuideText.Transcript(picture: picture))
        let size = raster.pixels.count
        if size <= Self.maximumCachedImageBytes {
            while order.count >= 4 || cachedImageBytes + size > Self.maximumCachedImageBytes {
                let oldest = order.removeFirst()
                if let evicted = cache.removeValue(forKey: oldest) {
                    cachedImageBytes -= evicted.image.width * evicted.image.height * 4
                }
            }
            cache[id] = result; order.append(id); cachedImageBytes += size
        }
        return result
    }

    func caption(_ link: CDUserGuide.Link) throws -> Caption {
        guard link.kind == .caption else { throw CDUserGuide.Failure.invalid("not a caption link") }
        let source = try picture(link.destination), rect = link.destinationRect, frame = source.frame
        let requested = QuickDrawRect(top: rect.top - frame.top, left: rect.left - frame.left,
                                      bottom: rect.bottom - frame.top, right: rect.right - frame.left)
        guard (1...4096).contains(requested.width), (1...4096).contains(requested.height) else {
            throw CDUserGuide.Failure.invalid("excessive caption dimensions")
        }
        let crop = QuickDrawRect(top: max(0, rect.top - frame.top), left: max(0, rect.left - frame.left),
            bottom: min(source.image.height, rect.bottom - frame.top), right: min(source.image.width, rect.right - frame.left))
        guard crop.width > 0, crop.height > 0, let bytes = source.image.dataProvider?.data,
              let pixels = CFDataGetBytePtr(bytes) else {
            throw CDUserGuide.Failure.invalid("caption lies outside its picture")
        }
        // One authored caption extends below its picture. Keep the requested
        // rectangle, including transparent padding, instead of shrinking it.
        var padded = [UInt8](repeating: 0, count: requested.width * requested.height * 4)
        for y in crop.top..<crop.bottom {
            let src = (y * source.image.width + crop.left) * 4
            let dst = ((y - requested.top) * requested.width + crop.left - requested.left) * 4
            padded.replaceSubrange(dst..<(dst + crop.width * 4),
                with: UnsafeBufferPointer(start: pixels + src, count: crop.width * 4))
        }
        guard let provider = CGDataProvider(data: Data(padded) as CFData),
              let image = CGImage(width: requested.width, height: requested.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: requested.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CDUserGuide.Failure.invalid("unable to display caption")
        }
        return Caption(image: image, text: source.text(in: requested))
    }

    /// Print the ordered main pages at 100%, on white paper. The reader's screen
    /// paper and caption popovers are not part of the original print document.
    /// Invisible text makes the imported prose selectable and searchable.
    func pdf(pageIndices: [Int], pixelLimit: Int = 64 * 1024 * 1024) throws -> Data {
        guard !pageIndices.isEmpty, pageIndices.count <= guide.pageIDs.count,
              pageIndices == Array(Set(pageIndices)).sorted(),
              pageIndices.allSatisfy({ guide.pageIDs.indices.contains($0) }),
              (1...64 * 1024 * 1024).contains(pixelLimit) else {
            throw CDUserGuide.Failure.invalid("invalid print page selection or work limit")
        }
        let output = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &media,
                [kCGPDFContextTitle: "On-line User’s Guide"] as CFDictionary) else {
            throw CDUserGuide.Failure.invalid("unable to create guide PDF")
        }
        var closed = false
        defer { if !closed { context.closePDF() } }
        var work = 0
        var numbering = CDUserGuideRules.State(guide: guide)
        func line(_ text: String, size: Int) -> CTLine {
            let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(max(1, min(128, size))), nil)
            return CTLineCreateWithAttributedString(NSAttributedString(string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        }
        for index in pageIndices {
            while numbering.pageIndex < index { numbering.page(forward: true) }
            let picture = try picture(guide.pageIDs[index])
            let cost = picture.image.width * picture.image.height
            guard cost <= pixelLimit - work else { throw CDUserGuide.Failure.invalid("excessive guide print work") }
            work += cost
            context.beginPDFPage(nil)
            context.saveGState()
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(media)
            context.interpolationQuality = .none
            context.draw(picture.image, in: CGRect(x: picture.paperOrigin.x, y: 792 - picture.image.height,
                width: picture.image.width, height: picture.image.height))
            context.setTextDrawingMode(.invisible)
            for source in picture.transcript.lines where !source.text.isEmpty {
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: picture.paperOrigin.x + source.x, y: 792 - source.y - 1)
                CTLineDraw(line(source.text, size: source.fontSize), context)
            }
            context.setTextDrawingMode(.fill); context.setFillColor(CGColor(gray: 0, alpha: 1))
            let number = line(numbering.pageNumber, size: 12)
            let width = CTLineGetTypographicBounds(number, nil, nil, nil)
            context.textPosition = CGPoint(x: (612 - width) / 2, y: 792.0 / 22)
            CTLineDraw(number, context)
            context.restoreGState(); context.endPDFPage()
            guard output.length <= 128 * 1024 * 1024 else { throw CDUserGuide.Failure.invalid("excessive guide PDF size") }
        }
        context.closePDF(); closed = true
        return output as Data
    }
}
