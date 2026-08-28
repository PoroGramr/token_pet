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
    public var framePercentPositions: [NormalizedPoint]?
    public var percentFontSize: Double
    public var framesPerSecond: Int
    public var schemaVersion: Int

    public init(
        id: UUID, name: String, frameCount: Int, frameOrder: [Int],
        removesLightBackground: Bool, percentPosition: NormalizedPoint,
        percentFontSize: Double, framesPerSecond: Int, schemaVersion: Int,
        framePercentPositions: [NormalizedPoint]? = nil
    ) {
        self.id = id
        self.name = name
        self.frameCount = frameCount
        self.frameOrder = frameOrder
        self.removesLightBackground = removesLightBackground
        self.percentPosition = percentPosition
        self.framePercentPositions = framePercentPositions
        self.percentFontSize = percentFontSize
        self.framesPerSecond = framesPerSecond
        self.schemaVersion = schemaVersion
    }

    public var resolvedFramePercentPositions: [NormalizedPoint] {
        guard frameCount >= 2 else { return [] }
        guard let framePercentPositions, framePercentPositions.count == frameCount else {
            return Array(repeating: percentPosition, count: frameCount)
        }
        return framePercentPositions
    }
}

public enum FramePercentPositionMapper {
    public static func ordered(
        positions: [NormalizedPoint],
        frameOrder: [Int]
    ) -> [NormalizedPoint] {
        guard positions.count == frameOrder.count,
              frameOrder.sorted() == Array(positions.indices) else {
            return []
        }
        return frameOrder.map { positions[$0] }
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
        if (3...4).contains(profile.frameCount) {
            if profile.frameOrder.sorted() != Array(0..<profile.frameCount) { errors.append("frameOrder") }
        } else {
            errors.append("frameCount")
            errors.append("frameOrder")
        }
        if !(0...1).contains(profile.percentPosition.x) || !(0...1).contains(profile.percentPosition.y) { errors.append("percentPosition") }
        if let framePercentPositions = profile.framePercentPositions {
            if framePercentPositions.count != profile.frameCount || framePercentPositions.contains(where: {
                !(0...1).contains($0.x) || !(0...1).contains($0.y)
            }) {
                errors.append("framePercentPositions")
            }
        }
        if !(10...36).contains(profile.percentFontSize) { errors.append("percentFontSize") }
        if profile.framesPerSecond != 3 { errors.append("framesPerSecond") }
        if profile.schemaVersion != 1 { errors.append("schemaVersion") }
        return errors
    }
}

public struct CharacterEditorDraftState: Equatable, Sendable {
    public let selectedID: UUID?
    public let draftID: UUID?
    public let isDirty: Bool

    public init(selectedID: UUID?, draftID: UUID?, isDirty: Bool) {
        self.selectedID = selectedID
        self.draftID = draftID
        self.isDirty = isDirty
    }
}

public enum CharacterEditorLoadedSelection: Equatable, Sendable {
    case builtIn(UUID)
    case draft(UUID)
}

public struct CharacterEditorCloseResult: Equatable, Sendable {
    public let state: CharacterEditorDraftState
    public let shouldClose: Bool

    public init(state: CharacterEditorDraftState, shouldClose: Bool) {
        self.state = state
        self.shouldClose = shouldClose
    }
}

public enum CharacterEditorStateTransitions {
    public static func afterSelectionAttempt(
        current: CharacterEditorDraftState,
        loadedSelection: CharacterEditorLoadedSelection?
    ) -> CharacterEditorDraftState {
        guard let loadedSelection else { return current }
        switch loadedSelection {
        case .builtIn(let id):
            return CharacterEditorDraftState(selectedID: id, draftID: nil, isDirty: false)
        case .draft(let id):
            return CharacterEditorDraftState(selectedID: id, draftID: id, isDirty: false)
        }
    }

    public static func afterCreatingDraft(
        current: CharacterEditorDraftState,
        newDraftID: UUID
    ) -> CharacterEditorDraftState {
        CharacterEditorDraftState(selectedID: newDraftID, draftID: newDraftID, isDirty: true)
    }

    public static func afterCloseReload(
        current: CharacterEditorDraftState,
        reloaded: CharacterEditorDraftState?
    ) -> CharacterEditorCloseResult {
        guard let reloaded, !reloaded.isDirty else {
            return CharacterEditorCloseResult(state: current, shouldClose: false)
        }
        return CharacterEditorCloseResult(state: reloaded, shouldClose: true)
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

    public static func textRect(
        containerSize: CGSize,
        position: NormalizedPoint,
        fontSize: Double,
        measuredTextSize: CGSize
    ) -> CGRect {
        let container = CGSize(
            width: max(0, containerSize.width),
            height: max(0, containerSize.height)
        )
        let content = CGSize(
            width: min(container.width, max(0, measuredTextSize.width)),
            height: min(container.height, max(max(0, measuredTextSize.height), CGFloat(max(0, fontSize))))
        )
        let clamped = clampedPosition(position)
        let centeredOrigin = CGPoint(
            x: container.width * clamped.x - content.width / 2,
            y: container.height * clamped.y - content.height / 2
        )
        return CGRect(
            x: min(max(0, centeredOrigin.x), container.width - content.width),
            y: min(max(0, centeredOrigin.y), container.height - content.height),
            width: content.width,
            height: content.height
        )
    }
}
