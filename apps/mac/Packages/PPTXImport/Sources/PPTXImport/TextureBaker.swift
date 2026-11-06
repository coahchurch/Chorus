import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TextureBaker {

    static let structuralPatterns: Set<String> = [
        "lgGrid", "smGrid", "dotGrid",
        "horz", "ltHorz", "narHorz", "dkHorz",
        "vert", "ltVert", "narVert", "dkVert",
        "cross", "diagCross",
        "lgCheck", "smCheck",
        "ltUpDiag", "ltDnDiag", "dkUpDiag", "dkDnDiag", "wdUpDiag", "wdDnDiag",
    ]

    static func bake(_ bake: TextureBake, canvasWidth: Int, canvasHeight: Int, to output: URL) -> Bool {
        guard canvasWidth > 0, canvasHeight > 0,
              let context = CGContext(
                  data: nil, width: canvasWidth, height: canvasHeight,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }

        switch bake.kind {
        case .texture(let sourcePath, let alpha, let scaleX, let scaleY, let tiled):
            guard drawTexture(
                sourcePath: sourcePath, alpha: alpha, scaleX: scaleX, scaleY: scaleY,
                tiled: tiled, k: bake.k,
                canvasWidth: canvasWidth, canvasHeight: canvasHeight, context: context)
            else { return false }
        case .duotone(let sourcePath, let darkHex, let lightHex, let alpha, let scaleX, let scaleY, let tiled):
            guard drawDuotone(
                sourcePath: sourcePath, darkHex: darkHex, lightHex: lightHex,
                alpha: alpha, scaleX: scaleX, scaleY: scaleY, tiled: tiled, k: bake.k,
                canvasWidth: canvasWidth, canvasHeight: canvasHeight, context: context)
            else { return false }
        case .pattern(let preset, let foregroundHex, let backgroundHex):
            drawPattern(
                preset: preset, foregroundHex: foregroundHex, backgroundHex: backgroundHex,
                k: bake.k, canvasWidth: canvasWidth, canvasHeight: canvasHeight, context: context)
        }

        guard let baked = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, baked, nil)
        return CGImageDestinationFinalize(destination)
    }

    private static func drawTexture(
        sourcePath: String, alpha: Double, scaleX: Double, scaleY: Double,
        tiled: Bool, k: Double,
        canvasWidth: Int, canvasHeight: Int, context: CGContext
    ) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.setAlpha(CGFloat(min(max(alpha, 0), 1)))

        let tileWidth = Double(image.width) * scaleX * k
        let tileHeight = Double(image.height) * scaleY * k
        guard tileWidth >= 1, tileHeight >= 1 else { return false }

        if tiled {
            var y = 0.0
            while y < Double(canvasHeight) {
                var x = 0.0
                while x < Double(canvasWidth) {
                    context.draw(image, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
                    x += tileWidth
                }
                y += tileHeight
            }
        } else {
            context.draw(image, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        }
        return true
    }

    private static func drawPattern(
        preset: String, foregroundHex: String, backgroundHex: String,
        k: Double, canvasWidth: Int, canvasHeight: Int, context: CGContext
    ) {
        let width = Double(canvasWidth)
        let height = Double(canvasHeight)
        context.setFillColor(cgColor(backgroundHex))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let fg = cgColor(foregroundHex)
        context.setFillColor(fg)
        context.setStrokeColor(fg)

        let cell = 8 * k
        let thin = max(1, k)
        let thick = max(2, 2 * k)

        func lines(horizontal: Bool, stride: Double, lineWidth: Double) {
            var position = 0.0
            let limit = horizontal ? height : width
            while position < limit {
                let rect = horizontal
                    ? CGRect(x: 0, y: position, width: width, height: lineWidth)
                    : CGRect(x: position, y: 0, width: lineWidth, height: height)
                context.fill(rect)
                position += stride
            }
        }

        func diagonals(up: Bool, stride: Double, lineWidth: Double) {
            context.setLineWidth(lineWidth)
            var offset = -height
            while offset < width {
                context.move(to: CGPoint(x: offset, y: up ? 0 : height))
                context.addLine(to: CGPoint(x: offset + height, y: up ? height : 0))
                context.strokePath()
                offset += stride
            }
        }

        switch preset {
        case "lgGrid":
            lines(horizontal: true, stride: cell, lineWidth: thin)
            lines(horizontal: false, stride: cell, lineWidth: thin)
        case "smGrid", "cross":
            lines(horizontal: true, stride: cell / 2, lineWidth: thin)
            lines(horizontal: false, stride: cell / 2, lineWidth: thin)
        case "dotGrid":
            var y = 0.0
            while y < height {
                var x = 0.0
                while x < width {
                    context.fill(CGRect(x: x, y: y, width: thin, height: thin))
                    x += cell
                }
                y += cell
            }
        case "horz", "ltHorz": lines(horizontal: true, stride: cell / 2, lineWidth: thin)
        case "narHorz": lines(horizontal: true, stride: cell / 4, lineWidth: thin)
        case "dkHorz": lines(horizontal: true, stride: cell / 2, lineWidth: thick)
        case "vert", "ltVert": lines(horizontal: false, stride: cell / 2, lineWidth: thin)
        case "narVert": lines(horizontal: false, stride: cell / 4, lineWidth: thin)
        case "dkVert": lines(horizontal: false, stride: cell / 2, lineWidth: thick)
        case "ltUpDiag": diagonals(up: true, stride: cell / 2, lineWidth: thin)
        case "ltDnDiag": diagonals(up: false, stride: cell / 2, lineWidth: thin)
        case "dkUpDiag": diagonals(up: true, stride: cell / 2, lineWidth: thick)
        case "dkDnDiag": diagonals(up: false, stride: cell / 2, lineWidth: thick)
        case "wdUpDiag": diagonals(up: true, stride: cell, lineWidth: thick)
        case "wdDnDiag": diagonals(up: false, stride: cell, lineWidth: thick)
        case "diagCross":
            diagonals(up: true, stride: cell / 2, lineWidth: thin)
            diagonals(up: false, stride: cell / 2, lineWidth: thin)
        case "lgCheck", "smCheck":
            let square = preset == "lgCheck" ? cell / 2 : cell / 4
            var y = 0.0
            var row = 0
            while y < height {
                var x = row.isMultiple(of: 2) ? 0.0 : square
                while x < width {
                    context.fill(CGRect(x: x, y: y, width: square, height: square))
                    x += square * 2
                }
                y += square
                row += 1
            }
        default:
            break
        }
    }

    private static func drawDuotone(
        sourcePath: String, darkHex: String, lightHex: String,
        alpha: Double, scaleX: Double, scaleY: Double, tiled: Bool, k: Double,
        canvasWidth: Int, canvasHeight: Int, context: CGContext
    ) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return false }
        let dark = channels(darkHex)
        let light = channels(lightHex)
        guard dark.count == 3, light.count == 3 else { return false }
        let (pixelCount, overflow) = canvasWidth.multipliedReportingOverflow(by: canvasHeight)
        guard !overflow, pixelCount <= Int.max / 4 else { return false }
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        let duotone = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let bitmap = CGContext(
                data: buffer.baseAddress, width: canvasWidth, height: canvasHeight,
                bitsPerComponent: 8, bytesPerRow: canvasWidth * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }

            bitmap.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
            let tileWidth = Double(image.width) * scaleX * k
            let tileHeight = Double(image.height) * scaleY * k
            guard tileWidth >= 1, tileHeight >= 1 else { return nil }
            if tiled {
                var y = 0.0
                while y < Double(canvasHeight) {
                    var x = 0.0
                    while x < Double(canvasWidth) {
                        bitmap.draw(image, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
                        x += tileWidth
                    }
                    y += tileHeight
                }
            } else {
                bitmap.draw(image, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
            }
            bitmap.flush()

            let bytes = buffer.bindMemory(to: UInt8.self)
            let opacity = min(max(alpha, 0), 1)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let sourceAlpha = Double(bytes[offset + 3]) / 255
                guard sourceAlpha > 0 else { continue }
                let red = Double(bytes[offset]) / 255 / sourceAlpha
                let green = Double(bytes[offset + 1]) / 255 / sourceAlpha
                let blue = Double(bytes[offset + 2]) / 255 / sourceAlpha
                let luminance = min(max(0.2126 * red + 0.7152 * green + 0.0722 * blue, 0), 1)
                let outputAlpha = sourceAlpha * opacity
                for channel in 0..<3 {
                    let color = dark[channel] * (1 - luminance) + light[channel] * luminance
                    bytes[offset + channel] = UInt8((color * outputAlpha * 255).rounded())
                }
                bytes[offset + 3] = UInt8((outputAlpha * 255).rounded())
            }
            return bitmap.makeImage()
        }
        guard let duotone else { return false }
        context.draw(duotone, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        return true
    }

    private static func channels(_ hex: String) -> [Double] {
        let value = String(hex.prefix(6))
        return stride(from: 0, to: 6, by: 2).compactMap { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: 2)
            return UInt8(value[start..<end], radix: 16).map { Double($0) / 255 }
        }
    }

    private static func cgColor(_ hex: String) -> CGColor {
        var padded = hex
        if padded.count == 6 { padded += "FF" }
        let values = stride(from: 0, to: 8, by: 2).compactMap { offset -> CGFloat? in
            let start = padded.index(padded.startIndex, offsetBy: offset)
            let end = padded.index(start, offsetBy: 2)
            return UInt8(padded[start..<end], radix: 16).map { CGFloat($0) / 255 }
        }
        guard values.count == 4 else { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
        return CGColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}
