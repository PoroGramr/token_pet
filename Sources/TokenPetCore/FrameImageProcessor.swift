import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FrameSequence {
    public static let indices = [1, 2, 3, 4, 5, 4, 3, 2]
    public static let framesPerSecond = 3

    public static func indices(frameCount: Int) -> [Int] {
        guard frameCount > 1 else { return Array(0..<max(0, frameCount)) }
        return Array(0..<frameCount) + Array(stride(from: frameCount - 2, through: 1, by: -1))
    }
}

public enum FrameImageError: Error, Equatable, Sendable {
    case invalidImage
    case contextCreationFailed
}

public enum FrameImageProcessor {
    public static func makeNormalizedPNG(from data: Data, pixelSize: Int) throws -> Data {
        guard pixelSize > 0 else { throw FrameImageError.invalidImage }
        let sourceImage = try makeTransparentImage(from: data)
        let bytesPerRow = pixelSize * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * pixelSize)
        guard let context = CGContext(
            data: &pixels,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FrameImageError.contextCreationFailed
        }
        context.interpolationQuality = .none
        let scale = min(
            CGFloat(pixelSize) / CGFloat(sourceImage.width),
            CGFloat(pixelSize) / CGFloat(sourceImage.height)
        )
        let size = CGSize(
            width: CGFloat(sourceImage.width) * scale,
            height: CGFloat(sourceImage.height) * scale
        )
        let rect = CGRect(
            x: (CGFloat(pixelSize) - size.width) / 2,
            y: (CGFloat(pixelSize) - size.height) / 2,
            width: size.width,
            height: size.height
        )
        context.draw(sourceImage, in: rect)
        guard let normalizedImage = context.makeImage() else {
            throw FrameImageError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FrameImageError.invalidImage
        }
        CGImageDestinationAddImage(destination, normalizedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FrameImageError.invalidImage
        }
        return output as Data
    }

    public static func makeTransparentImage(from data: Data) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw FrameImageError.invalidImage
        }

        if sourceImage.alphaInfo.hasTransparency {
            return sourceImage
        }

        let width = sourceImage.width
        let height = sourceImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FrameImageError.contextCreationFailed
        }

        context.interpolationQuality = .none
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        removeConnectedBackground(from: &pixels, width: width, height: height)

        let output = Data(pixels)
        guard
            let provider = CGDataProvider(data: output as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw FrameImageError.invalidImage
        }
        return image
    }

    private static func removeConnectedBackground(from pixels: inout [UInt8], width: Int, height: Int) {
        var visited = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        queue.reserveCapacity(width * 2 + height * 2)

        func isBackground(_ index: Int) -> Bool {
            let offset = index * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let brightest = max(red, green, blue)
            let darkest = min(red, green, blue)
            return darkest >= 205 && brightest - darkest <= 16
        }

        func appendIfBackground(_ index: Int) {
            guard !visited[index], isBackground(index) else { return }
            visited[index] = true
            queue.append(index)
        }

        for x in 0..<width {
            appendIfBackground(x)
            appendIfBackground((height - 1) * width + x)
        }
        for y in 0..<height {
            appendIfBackground(y * width)
            appendIfBackground(y * width + width - 1)
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            if x > 0 { appendIfBackground(index - 1) }
            if x + 1 < width { appendIfBackground(index + 1) }
            if y > 0 { appendIfBackground(index - width) }
            if y + 1 < height { appendIfBackground(index + width) }
        }

        for index in queue {
            pixels[index * 4 + 3] = 0
        }
    }
}

private extension CGImageAlphaInfo {
    var hasTransparency: Bool {
        switch self {
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            return true
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        @unknown default:
            return false
        }
    }
}
