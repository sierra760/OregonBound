import Foundation
import CoreGraphics
import CoreText

/// Platform adapter for the one outline strike used by the imported guide.
/// All page composition, bitmap fonts, spacing and clipping remain deterministic
/// in CDGuideRaster. The original font is decoded locally, never registered.
enum CDGuideDrawing {
    static func fonts(_ source: CDGuideFonts) throws -> [CDGuideFonts.Key: CDGuideRaster.Font] {
        var fonts: [CDGuideFonts.Key: CDGuideRaster.Font] = [:]
        for selection in CDGuideFonts.selections {
            guard let data = source.resources[selection.key] else { throw CDGuidePicture.Failure.invalid("missing guide font") }
            if selection.type == "sfnt" { fonts[selection.key] = try outlineFont(data: data) }
            else {
                let strike = try BitmapFontExtractor.parseNFNT(data, resourceID: selection.key.family)
                fonts[selection.key] = try CDGuideRaster.Font(strike: strike)
            }
        }
        return fonts
    }

    static func outlineFont(data: Data) throws -> CDGuideRaster.Font {
        guard data.count == 44416, SHA256Hex.digest(data) == CDGuideOutlineFont.expectedSHA256 else {
            throw CDGuidePicture.Failure.invalid("guide outline does not match the verified System font")
        }
        let metrics = try CDGuideOutlineFont(data: data)
        guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
              let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw CDGuidePicture.Failure.invalid("unable to create guide outline rasterizer")
        }
        let nativeFont = CTFontCreateWithGraphicsFont(font, CGFloat(metrics.pointSize), nil, nil)
        context.setShouldAntialias(false); context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false); context.setAllowsFontSmoothing(false)
        context.setShouldSubpixelPositionFonts(false); context.setAllowsFontSubpixelPositioning(false)
        context.setShouldSubpixelQuantizeFonts(false); context.setAllowsFontSubpixelQuantization(false)
        var glyphs: [CDGuideRaster.Glyph] = [], cache: [UInt16: CDGuideRaster.Glyph] = [:]
        for id in metrics.glyphIDs {
            if let existing = cache[id] { glyphs.append(existing); continue }
            var glyph = CGGlyph(id), position = CGPoint(x: 8, y: 12), bounds = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(nativeFont, .horizontal, &glyph, &bounds, 1)
            guard bounds.minX >= -8, bounds.maxX <= 24, bounds.minY >= -12, bounds.maxY <= 20 else {
                throw CDGuidePicture.Failure.invalid("guide outline glyph exceeds its raster bounds")
            }
            context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            context.setFillColor(CGColor(gray: 1, alpha: 1)); CTFontDrawGlyphs(nativeFont, &glyph, &position, 1, context)
            let ink = Array(UnsafeBufferPointer(start: pixels, count: 32 * 32))
            guard ink.allSatisfy({ $0 == 0 || $0 == 255 }) else {
                throw CDGuidePicture.Failure.invalid("outline rasterizer did not produce monochrome glyphs")
            }
            let rendered = CDGuideRaster.Glyph(width: 32, height: 32, bearingX: -8, ink: ink)
            cache[id] = rendered; glyphs.append(rendered)
        }
        return CDGuideRaster.Font(advances: metrics.advances, ascent: 20, glyphs: glyphs)
    }
}
