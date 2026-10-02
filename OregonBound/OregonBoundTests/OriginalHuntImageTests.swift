import CoreGraphics
import Foundation
import Testing
@testable import OregonBound

struct OriginalHuntImageTests {
    @Test func monochromeMaskKeepsEnclosedWhiteAndSkipsColorPalette() throws {
        // Five one-bit rows: white border, black ring, enclosed white center.
        let bits = Data([0b11111000, 0b10001000, 0b10101000, 0b10001000, 0b11111000])
        let image = try #require(CGImage(width: 5, height: 5, bitsPerComponent: 1, bitsPerPixel: 1,
            bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
            provider: CGDataProvider(data: bits as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let palette = OriginalHuntSession.palette(destination: 2, month: 4, weather: 3, snow: true)
        let unchanged = try #require(OriginalHuntImage.substitutingPalette(in: image, palette: palette, monochrome: true))
        #expect(unchanged.dataProvider!.data! as Data == bits)
        let masked = try #require(OriginalRiverScene.maskedImage(unchanged))
        let pixels = Array(masked.dataProvider!.data! as Data)
        #expect(pixels[3] == 0)
        #expect(Array(pixels[48..<52]) == [255,255,255,255])
        #expect(Array(pixels[24..<28]) == [0,0,0,255])
    }

    @Test func replacementsPreserveOriginalIndicesAndOtherPaletteColors() throws {
        var table: [UInt8] = []
        for index in 0..<256 {
            table.append(UInt8(index))
            table.append(UInt8(255 - index))
            table.append(UInt8(index / 2))
        }
        let sourceSpace = try #require(CGColorSpace(indexedBaseSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                   last: 255,colorTable: &table))
        let data = Data([0,1,2,42,255])
        let provider = try #require(CGDataProvider(data: data as CFData))
        let source = try #require(CGImage(width: 5,height: 1,bitsPerComponent: 8,bitsPerPixel: 8,
            bytesPerRow: 5,space: sourceSpace,bitmapInfo: [],provider: provider,decode: nil,
            shouldInterpolate: false,intent: .defaultIntent))
        for (snow,weather) in [(false,0),(false,3),(true,0)] {
            let palette = OriginalHuntSession.palette(destination: 2,month: 4,weather: weather,snow: snow)
            let result = try #require(OriginalHuntImage.substitutingPalette(in: source,palette: palette))
            let colors = try #require(result.colorSpace?.colorTable)
            #expect(result.dataProvider?.data as Data? == data)
            for index in 0..<256 {
                let origin = index == 1 ? palette.skyIndex : index == 2 ? palette.groundIndex : index
                #expect(Array(colors[index*3..<index*3+3]) == Array(table[origin*3..<origin*3+3]))
            }
            let fixed = try #require(OriginalHuntImage.substitutingPalette(in: source, palette: palette, resourceType: "Ima4"))
            #expect(fixed.colorSpace?.colorTable == table)
            #expect(fixed.dataProvider?.data as Data? == data)
            #expect(source.colorSpace?.colorTable == table)
        }
    }

    @Test func maskedWhiteEnclosuresRemainOpaque() throws {
        // Original CalcCMask keeps enclosed white; only edge-connected white is transparent.
        let white = [UInt8](repeating: 255,count: 4), black: [UInt8] = [0,0,0,255]
        let pixels = (0..<25).flatMap { index -> [UInt8] in
            let x = index%5,y = index/5
            return (x == 0 || y == 0 || x == 4 || y == 4 || x == 2 && y == 2) ? white : black
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: 5,height: 5,bitsPerComponent: 8,bitsPerPixel: 32,
            bytesPerRow: 20,space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        let masked = try #require(OriginalRiverScene.maskedImage(image))
        let data = try #require(masked.dataProvider?.data) as Data
        #expect(data[3] == 0)
        #expect(data[(2*5+2)*4+3] == 255)
        #expect(data[(1*5+1)*4+3] == 255)
    }
}
