import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PPTXImport

struct TextureBakerTests {
    @Test func lgGridBakesFieldAndLines() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: output) }
        let bake = TextureBake(
            placeholderID: "p",
            kind: .pattern(preset: "lgGrid", foregroundHex: "000000FF", backgroundHex: "FFFFFFFF"),
            k: 2)
        #expect(TextureBaker.bake(bake, canvasWidth: 64, canvasHeight: 64, to: output))

        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let context = try #require(CGContext(
            data: &pixels, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))

        func red(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * 64 + x) * 4] }

        #expect(red(1, 1) < 40, "grid line is foreground ink")
        #expect(red(8, 8) > 215, "cell interior is the background field")
        #expect(red(17, 8) < 40, "next grid line lands one cell over")
    }

    @Test func duotoneMapsBlackAndWhiteToTheRequestedColors() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-source.png")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-duotone.png")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let sourceContext = try #require(CGContext(
            data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        sourceContext.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        sourceContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        sourceContext.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        sourceContext.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let sourceImage = try #require(sourceContext.makeImage())
        let sourceDestination = try #require(CGImageDestinationCreateWithURL(
            sourceURL as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(sourceDestination, sourceImage, nil)
        #expect(CGImageDestinationFinalize(sourceDestination))

        let bake = TextureBake(
            placeholderID: "duotone",
            kind: .duotone(
                sourcePath: sourceURL.path, darkHex: "302050FF", lightHex: "E0B0D0FF",
                alpha: 1, scaleX: 1, scaleY: 1, tiled: false),
            k: 1)
        #expect(TextureBaker.bake(bake, canvasWidth: 2, canvasHeight: 1, to: outputURL))

        let outputSource = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let outputImage = try #require(CGImageSourceCreateImageAtIndex(outputSource, 0, nil))
        var pixels = [UInt8](repeating: 0, count: 8)
        let outputContext = try #require(CGContext(
            data: &pixels, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        outputContext.draw(outputImage, in: CGRect(x: 0, y: 0, width: 2, height: 1))

        #expect(Array(pixels[0..<3]) == [0x30, 0x20, 0x50])
        #expect(Array(pixels[4..<7]) == [0xE0, 0xB0, 0xD0])
    }
}
