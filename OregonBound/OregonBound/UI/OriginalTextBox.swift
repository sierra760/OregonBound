import SwiftUI

/// Recovered Roman TextBox ink placement in an authored static-text rectangle.
struct OriginalTextBox: View {
    let text: String
    var font: BitmapFont? = .bold14
    let width: Int
    let height: Int
    var centered = false

    var body: some View {
        Group {
            if let font, let data = text.data(using: .macOSRoman),
               let widths = font.prefixWidths(text),
               let lines = try? OriginalStaticTextLayout.lines(bytes: Array(data), prefixWidths: widths,
                    width: width, lineHeight: font.lineHeight, centered: centered) {
                let bytes = Array(data)
                // lpch15's fast path draws directly in the current port without
                // installing the authored item rect as a clip. Full TE does clip.
                let fast = OriginalStaticTextLayout.usesFastPath(bytes: bytes, textWidth: widths.last!, width: width)
                let drawingHeight = fast ? max(height, font.metrics.header.rect_height) : height
                Canvas { context, _ in
                    for line in lines {
                        for index in line.start..<line.end where bytes[index] != 13 {
                            let character = bytes[index] == 10 ? "\u{fffd}" : String(data: Data([bytes[index]]), encoding: .macOSRoman)!
                            for glyph in font.layout(character).glyphs {
                                let rect = glyph.rect.offsetBy(dx: CGFloat(line.x + widths[index] - widths[line.start]),
                                                               dy: CGFloat(line.y))
                                context.draw(Image(decorative: glyph.image, scale: 1).interpolation(.none), in: rect)
                            }
                        }
                    }
                }.frame(width: CGFloat(width), height: CGFloat(drawingHeight)).clipped()
            } else {
                // Compatibility for names from older Unicode-native saves.
                OriginalText(text: text, font: font, width: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .top : .topLeading)
                    .clipped()
            }
        }.frame(width: CGFloat(width), height: CGFloat(height), alignment: .topLeading)
            .accessibilityLabel(text)
    }
}
