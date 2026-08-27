import Foundation

public struct CharacterDraftValidation: Equatable, Sendable {
    public let errors: [String]

    public var isValid: Bool { errors.isEmpty }

    public init(errors: [String]) {
        self.errors = errors
    }
}

public struct CharacterDraft: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceFrames: [Data]
    public var displayFrames: [Data]
    public var removesLightBackground: Bool
    public var percentPosition: NormalizedPoint
    public var percentFontSize: Double

    public init(
        id: UUID,
        name: String,
        sourceFrames: [Data],
        displayFrames: [Data],
        removesLightBackground: Bool,
        percentPosition: NormalizedPoint,
        percentFontSize: Double
    ) {
        self.id = id
        self.name = name
        self.sourceFrames = sourceFrames
        self.displayFrames = displayFrames
        self.removesLightBackground = removesLightBackground
        self.percentPosition = percentPosition
        self.percentFontSize = percentFontSize
    }

    public static func new(name: String = "새 캐릭터", sourceFrames: [Data] = []) -> CharacterDraft {
        CharacterDraft(
            id: UUID(),
            name: name,
            sourceFrames: sourceFrames,
            displayFrames: sourceFrames,
            removesLightBackground: false,
            percentPosition: NormalizedPoint(x: 0.5, y: 0.5),
            percentFontSize: 22
        )
    }

    public init(assets: CharacterAssets) {
        self.init(
            id: assets.profile.id,
            name: assets.profile.name,
            sourceFrames: assets.sources,
            displayFrames: assets.frames,
            removesLightBackground: assets.profile.removesLightBackground,
            percentPosition: assets.profile.percentPosition,
            percentFontSize: assets.profile.percentFontSize
        )
    }

    public mutating func moveFrame(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceFrames.indices.contains(sourceIndex), sourceFrames.indices.contains(destinationIndex) else { return }
        sourceFrames.insert(sourceFrames.remove(at: sourceIndex), at: destinationIndex)
        if displayFrames.count == sourceFrames.count {
            displayFrames.insert(displayFrames.remove(at: sourceIndex), at: destinationIndex)
        }
    }

    public func validation(existingNames: [String]) -> CharacterDraftValidation {
        var errors = CharacterProfileValidator.validate(profile, existingNames: existingNames)
        if displayFrames.count != sourceFrames.count {
            errors.append("displayFrames")
        }
        return CharacterDraftValidation(errors: errors)
    }

    public var profile: CharacterProfile {
        CharacterProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            frameCount: sourceFrames.count,
            frameOrder: Array(sourceFrames.indices),
            removesLightBackground: removesLightBackground,
            percentPosition: PercentLayout.clampedPosition(percentPosition),
            percentFontSize: percentFontSize,
            framesPerSecond: FrameSequence.framesPerSecond,
            schemaVersion: 1
        )
    }
}
