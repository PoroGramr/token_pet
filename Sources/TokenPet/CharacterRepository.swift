import AppKit
import TokenPetCore

struct RuntimeCharacter {
    let profile: CharacterProfile
    let frames: [NSImage]
    let playbackIndices: [Int]
}

@MainActor
final class CharacterRepository {
    static let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let store: CharacterStore
    private let menuResolver: CharacterMenuResolver

    init(store: CharacterStore) {
        self.store = store
        menuResolver = CharacterMenuResolver(catalog: store, builtInProfile: Self.builtInProfile)
    }

    func availableCharacters() throws -> [CharacterProfile] {
        [Self.builtInProfile] + (try store.list())
    }

    func characterMenuPresentation() throws -> CharacterMenuSnapshot {
        try menuResolver.presentation()
    }

    var persistedSelectedCharacterID: UUID? {
        store.selectedCharacterID
    }

    func selectedCharacter() -> RuntimeCharacter {
        guard let selectedID = store.selectedCharacterID else {
            return builtInCharacter()
        }
        do {
            let profiles = try store.list()
            guard profiles.contains(where: { $0.id == selectedID }) else {
                store.selectedCharacterID = nil
                return builtInCharacter()
            }
            return try select(id: selectedID)
        } catch {
            return builtInCharacter()
        }
    }

    func select(id: UUID?) throws -> RuntimeCharacter {
        guard let id, id != Self.builtInID else {
            store.selectedCharacterID = nil
            return builtInCharacter()
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
        let character = RuntimeCharacter(
            profile: assets.profile,
            frames: frames,
            playbackIndices: FrameSequence.indices(frameCount: frames.count)
        )
        store.selectedCharacterID = id
        return character
    }

    private func builtInCharacter() -> RuntimeCharacter {
        RuntimeCharacter(
            profile: Self.builtInProfile,
            frames: Self.loadBuiltInFrames(),
            playbackIndices: FrameSequence.indices(frameCount: 4)
        )
    }

    private static let builtInProfile = CharacterProfile(
        id: builtInID,
        name: "기본 캐릭터",
        frameCount: 4,
        frameOrder: [0, 1, 2, 3],
        removesLightBackground: true,
        percentPosition: NormalizedPoint(x: 0.5, y: 52.0 / 120.0),
        percentFontSize: 22,
        framesPerSecond: FrameSequence.framesPerSecond,
        schemaVersion: 1
    )

    private static func loadBuiltInFrames() -> [NSImage] {
        (1...4).compactMap { index in
            guard let url = builtInFrameURL(index: index),
                  let data = try? Data(contentsOf: url),
                  let image = try? FrameImageProcessor.makeTransparentImage(from: data) else {
                return nil
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    private static func builtInFrameURL(index: Int) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Frames/\(index).png")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("img/\(index).png")
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }
}
