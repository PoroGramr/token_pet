import AppKit
import TokenPetCore

struct RuntimeCharacter {
    let profile: CharacterProfile
    let frames: [NSImage]
    let framePercentPositions: [NormalizedPoint]
    let playbackIndices: [Int]
}

@MainActor
final class CharacterRepository {
    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let mushroomBuiltInID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let builtInIDs: Set<UUID> = [builtInID, mushroomBuiltInID]

    private struct BuiltInCharacterDefinition {
        let profile: CharacterProfile
        let framePaths: [String]
    }

    private let store: CharacterStore
    private let builtInSettings: BuiltInCharacterSettings

    init(store: CharacterStore, builtInSettings: BuiltInCharacterSettings) {
        self.store = store
        self.builtInSettings = builtInSettings
    }

    func availableCharacters() throws -> [CharacterProfile] {
        Self.builtInDefinitions.map(\.profile) + (try store.list())
    }

    func characterMenuPresentation() throws -> CharacterMenuSnapshot {
        CharacterMenuPresentation.make(
            profiles: try availableCharacters(),
            builtInID: Self.builtInID,
            selectedID: store.selectedCharacterID
        )
    }

    var persistedSelectedCharacterID: UUID? {
        store.selectedCharacterID
    }

    func selectedCharacter() -> RuntimeCharacter {
        guard let selectedID = store.selectedCharacterID else {
            return builtInCharacter(id: Self.builtInID)
        }
        do {
            if Self.builtInIDs.contains(selectedID) {
                return try select(id: selectedID)
            }
            guard try store.list().contains(where: { $0.id == selectedID }) else {
                store.selectedCharacterID = nil
                return builtInCharacter(id: Self.builtInID)
            }
            return try select(id: selectedID)
        } catch {
            return builtInCharacter(id: Self.builtInID)
        }
    }

    func select(id: UUID?) throws -> RuntimeCharacter {
        guard let id else {
            store.selectedCharacterID = nil
            return builtInCharacter(id: Self.builtInID)
        }
        if Self.builtInIDs.contains(id) {
            let character = try builtInCharacterThrowing(id: id)
            store.selectedCharacterID = id == Self.builtInID ? nil : id
            return character
        }

        let assets = try store.load(id: id)
        let frames = try assets.profile.frameOrder.map { index -> NSImage in
            guard assets.frames.indices.contains(index), let image = NSImage(data: assets.frames[index]) else {
                throw CharacterStoreError.unreadableAssets
            }
            return image
        }
        guard frames.count == assets.profile.frameCount else {
            throw CharacterStoreError.unreadableAssets
        }
        let positions = FramePercentPositionMapper.ordered(
            positions: assets.profile.resolvedFramePercentPositions,
            frameOrder: assets.profile.frameOrder
        )
        guard positions.count == frames.count else {
            throw CharacterStoreError.unreadableAssets
        }
        let character = RuntimeCharacter(
            profile: assets.profile,
            frames: frames,
            framePercentPositions: positions,
            playbackIndices: FrameSequence.indices(frameCount: frames.count)
        )
        store.selectedCharacterID = id
        return character
    }

    private func builtInCharacter(id: UUID) -> RuntimeCharacter {
        (try? builtInCharacterThrowing(id: id)) ?? RuntimeCharacter(
            profile: Self.batteryProfile,
            frames: [],
            framePercentPositions: [],
            playbackIndices: []
        )
    }

    private func builtInCharacterThrowing(id: UUID) throws -> RuntimeCharacter {
        guard let definition = Self.builtInDefinitions.first(where: { $0.profile.id == id }) else {
            throw CharacterStoreError.unreadableAssets
        }
        let frames = try definition.framePaths.map { path -> NSImage in
            guard let url = Self.builtInFrameURL(path: path),
                  let data = try? Data(contentsOf: url),
                  let image = try? FrameImageProcessor.makeTransparentImage(from: data) else {
                throw CharacterStoreError.unreadableAssets
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        var profile = definition.profile
        profile.framePercentPositions = builtInSettings.positions(for: definition.profile)
        profile.percentPosition = profile.framePercentPositions?.first ?? definition.profile.percentPosition
        return RuntimeCharacter(
            profile: profile,
            frames: frames,
            framePercentPositions: profile.resolvedFramePercentPositions,
            playbackIndices: FrameSequence.indices(frameCount: frames.count)
        )
    }

    func builtInCharacterPreview(id: UUID) throws -> RuntimeCharacter {
        try builtInCharacterThrowing(id: id)
    }

    private static let batteryProfile = CharacterProfile(
        id: builtInID,
        name: "배터리",
        frameCount: 4,
        frameOrder: [0, 1, 2, 3],
        removesLightBackground: true,
        percentPosition: NormalizedPoint(x: 0.5, y: 52.0 / 120.0),
        percentFontSize: 22,
        framesPerSecond: FrameSequence.framesPerSecond,
        schemaVersion: 1,
        framePercentPositions: Array(repeating: NormalizedPoint(x: 0.5, y: 52.0 / 120.0), count: 4)
    )

    private static let mushroomProfile = CharacterProfile(
        id: mushroomBuiltInID,
        name: "버섯",
        frameCount: 3,
        frameOrder: [0, 1, 2],
        removesLightBackground: false,
        percentPosition: NormalizedPoint(x: 0.5, y: 0.52),
        percentFontSize: 22,
        framesPerSecond: FrameSequence.framesPerSecond,
        schemaVersion: 1,
        framePercentPositions: Array(repeating: NormalizedPoint(x: 0.5, y: 0.52), count: 3)
    )

    private static let builtInDefinitions: [BuiltInCharacterDefinition] = [
        .init(profile: batteryProfile, framePaths: ["battery/1.png", "battery/2.png", "battery/3.png", "battery/4.png"]),
        .init(profile: mushroomProfile, framePaths: [
            "mushroom/orange-mushroom-idle.png",
            "mushroom/orange-mushroom-airborne.png",
            "mushroom/orange-mushroom-landing.png"
        ])
    ]

    private static func builtInFrameURL(path: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Frames/\(path)")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("img/\(path)")
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }
}
