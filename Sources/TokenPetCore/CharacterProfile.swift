import CoreGraphics
import Foundation

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CharacterProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var frameCount: Int
    public var frameOrder: [Int]
    public var removesLightBackground: Bool
    public var percentPosition: NormalizedPoint
    public var percentFontSize: Double
    public var framesPerSecond: Int
    public var schemaVersion: Int

    public init(
        id: UUID, name: String, frameCount: Int, frameOrder: [Int],
        removesLightBackground: Bool, percentPosition: NormalizedPoint,
        percentFontSize: Double, framesPerSecond: Int, schemaVersion: Int
    ) {
        self.id = id
        self.name = name
        self.frameCount = frameCount
        self.frameOrder = frameOrder
        self.removesLightBackground = removesLightBackground
        self.percentPosition = percentPosition
        self.percentFontSize = percentFontSize
        self.framesPerSecond = framesPerSecond
        self.schemaVersion = schemaVersion
    }
}

public enum CharacterProfileValidator {
    public static func validate(_ profile: CharacterProfile, existingNames: [String]) -> [String] {
        var errors: [String] = []
        let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(1...40).contains(trimmedName.count) { errors.append("name") }
        let foldedName = trimmedName.localizedLowercase
        if existingNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == foldedName }) {
            errors.append("duplicateName")
        }
        if !(3...4).contains(profile.frameCount) { errors.append("frameCount") }
        if profile.frameOrder != Array(0..<profile.frameCount) { errors.append("frameOrder") }
        if !(0...1).contains(profile.percentPosition.x) || !(0...1).contains(profile.percentPosition.y) { errors.append("percentPosition") }
        if !(10...36).contains(profile.percentFontSize) { errors.append("percentFontSize") }
        if profile.framesPerSecond != 3 { errors.append("framesPerSecond") }
        if profile.schemaVersion != 1 { errors.append("schemaVersion") }
        return errors
    }
}

public enum PercentLayout {
    public static func clampedPosition(_ position: NormalizedPoint) -> NormalizedPoint {
        NormalizedPoint(x: min(1, max(0, position.x)), y: min(1, max(0, position.y)))
    }

    public static func origin(containerSize: CGSize, position: NormalizedPoint, contentSize: CGSize) -> CGPoint {
        let availableWidth = max(0, containerSize.width - contentSize.width)
        let availableHeight = max(0, containerSize.height - contentSize.height)
        let clamped = clampedPosition(position)
        return CGPoint(x: availableWidth * clamped.x, y: availableHeight * clamped.y)
    }

    public static func origin(containerSize: CGSize, position: NormalizedPoint) -> CGPoint {
        let clamped = clampedPosition(position)
        return CGPoint(x: containerSize.width * clamped.x, y: containerSize.height * clamped.y)
    }

    public static func origin(containerSize: CGSize, contentSize: CGSize, position: NormalizedPoint) -> CGPoint {
        origin(containerSize: containerSize, position: position, contentSize: contentSize)
    }
}
