import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CharacterRuntimeAssetError: Error, Equatable, Sendable {
    case invalidAssetCount
    case invalidFrameOrder
    case undecodableSource(Int)
    case undecodableFrame(Int)
}

public enum CharacterPNGAssetValidator {
    public static let requiredPixelSize = 240

    public static func isValid(_ data: Data) -> Bool {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            CGImageSourceGetCount(source) == 1,
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            ),
            image.width == requiredPixelSize,
            image.height == requiredPixelSize
        else {
            return false
        }
        return true
    }
}

public enum CharacterRuntimeAssetValidator {
    public static func validate(_ assets: CharacterAssets) throws {
        let profile = assets.profile
        guard
            (3...4).contains(profile.frameCount),
            assets.sources.count == profile.frameCount,
            assets.frames.count == profile.frameCount
        else {
            throw CharacterRuntimeAssetError.invalidAssetCount
        }
        guard profile.frameOrder.sorted() == Array(0..<profile.frameCount) else {
            throw CharacterRuntimeAssetError.invalidFrameOrder
        }

        for frameIndex in 0..<profile.frameCount {
            guard CharacterPNGAssetValidator.isValid(assets.sources[frameIndex]) else {
                throw CharacterRuntimeAssetError.undecodableSource(frameIndex)
            }
            guard CharacterPNGAssetValidator.isValid(assets.frames[frameIndex]) else {
                throw CharacterRuntimeAssetError.undecodableFrame(frameIndex)
            }
        }
    }
}
