import Foundation
import ImageIO

public enum CharacterRuntimeAssetError: Error, Equatable, Sendable {
    case invalidAssetCount
    case invalidFrameOrder
    case undecodableFrame(Int)
}

public enum CharacterRuntimeAssetValidator {
    public static func validate(_ assets: CharacterAssets) throws {
        let profile = assets.profile
        guard assets.frames.count == profile.frameCount else {
            throw CharacterRuntimeAssetError.invalidAssetCount
        }
        guard profile.frameOrder.sorted() == Array(0..<profile.frameCount) else {
            throw CharacterRuntimeAssetError.invalidFrameOrder
        }

        for frameIndex in profile.frameOrder {
            let data = assets.frames[frameIndex]
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                CGImageSourceGetCount(source) > 0,
                CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
            else {
                throw CharacterRuntimeAssetError.undecodableFrame(frameIndex)
            }
        }
    }
}
