import Foundation

public struct CharacterAssets: Equatable, Sendable {
    public var profile: CharacterProfile
    public var sources: [Data]
    public var frames: [Data]

    public init(profile: CharacterProfile, sources: [Data], frames: [Data]) {
        self.profile = profile
        self.sources = sources
        self.frames = frames
    }
}

public enum CharacterStoreError: Error, Equatable, Sendable {
    case invalidProfile([String])
    case invalidAssetCount
    case reservedBuiltInCharacter
    case notFound
    case unreadableAssets
    case persistenceFailed
}

public final class CharacterStore: @unchecked Sendable {
    public static let builtInCharacterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let rootURL: URL
    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private let selectedCharacterIDKey = "TokenPet.selectedCharacterID"

    public init(rootURL: URL, defaults: UserDefaults) {
        self.rootURL = rootURL
        self.defaults = defaults
    }

    public var selectedCharacterID: UUID? {
        get {
            guard let value = defaults.string(forKey: selectedCharacterIDKey) else { return nil }
            return UUID(uuidString: value)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: selectedCharacterIDKey)
            } else {
                defaults.removeObject(forKey: selectedCharacterIDKey)
            }
        }
    }

    public func list() throws -> [CharacterProfile] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        do {
            let entries = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let profiles = entries.compactMap { url -> CharacterProfile? in
                guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
                return try? readAssets(at: url, expectedID: id).profile
            }
            return profiles.sorted {
                let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameOrder == .orderedSame {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return nameOrder == .orderedAscending
            }
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    public func load(id: UUID) throws -> CharacterAssets {
        do {
            return try readAssets(at: directoryURL(for: id), expectedID: id)
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.unreadableAssets
        }
    }

    public func save(_ assets: CharacterAssets) throws {
        guard assets.profile.id != Self.builtInCharacterID else {
            throw CharacterStoreError.reservedBuiltInCharacter
        }
        guard assets.sources.count == assets.profile.frameCount,
              assets.frames.count == assets.profile.frameCount
        else {
            throw CharacterStoreError.invalidAssetCount
        }

        let existingProfiles = try list().filter { $0.id != assets.profile.id }
        let validationErrors = CharacterProfileValidator.validate(
            assets.profile,
            existingNames: existingProfiles.map(\.name)
        )
        guard validationErrors.isEmpty else {
            throw CharacterStoreError.invalidProfile(validationErrors)
        }

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let stagingURL = rootURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            var stagingNeedsCleanup = true
            defer {
                if stagingNeedsCleanup {
                    try? fileManager.removeItem(at: stagingURL)
                }
            }

            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            try write(assets, to: stagingURL)
            guard try readAssets(at: stagingURL, expectedID: assets.profile.id) == assets else {
                throw CharacterStoreError.persistenceFailed
            }

            let targetURL = directoryURL(for: assets.profile.id)
            let backupURL = rootURL.appendingPathComponent(".backup-\(assets.profile.id.uuidString)-\(UUID().uuidString)", isDirectory: true)
            var backupExists = false
            var replacementCommitted = false
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.moveItem(at: targetURL, to: backupURL)
                    backupExists = true
                }
                try fileManager.moveItem(at: stagingURL, to: targetURL)
                stagingNeedsCleanup = false
                replacementCommitted = true
                if backupExists {
                    try fileManager.removeItem(at: backupURL)
                }
            } catch {
                if replacementCommitted {
                    try? fileManager.removeItem(at: targetURL)
                }
                if backupExists {
                    try? fileManager.moveItem(at: backupURL, to: targetURL)
                }
                throw CharacterStoreError.persistenceFailed
            }
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    public func delete(id: UUID) throws {
        guard id != Self.builtInCharacterID else {
            throw CharacterStoreError.reservedBuiltInCharacter
        }
        let targetURL = directoryURL(for: id)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw CharacterStoreError.notFound
        }
        do {
            try fileManager.removeItem(at: targetURL)
            if selectedCharacterID == id {
                selectedCharacterID = nil
            }
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    private func directoryURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func write(_ assets: CharacterAssets, to directoryURL: URL) throws {
        let profileData = try JSONEncoder().encode(assets.profile)
        try profileData.write(to: directoryURL.appendingPathComponent("profile.json"), options: .atomic)
        for index in assets.sources.indices {
            try assets.sources[index].write(
                to: directoryURL.appendingPathComponent("source-\(index + 1).png"),
                options: .atomic
            )
        }
        for index in assets.frames.indices {
            try assets.frames[index].write(
                to: directoryURL.appendingPathComponent("frame-\(index + 1).png"),
                options: .atomic
            )
        }
    }

    private func readAssets(at directoryURL: URL, expectedID: UUID) throws -> CharacterAssets {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CharacterStoreError.notFound
        }
        let profileURL = directoryURL.appendingPathComponent("profile.json")
        guard let profile = try? JSONDecoder().decode(CharacterProfile.self, from: Data(contentsOf: profileURL)),
              profile.id == expectedID,
              CharacterProfileValidator.validate(profile, existingNames: []).isEmpty
        else {
            throw CharacterStoreError.unreadableAssets
        }

        do {
            let sources = try (0..<profile.frameCount).map {
                try Data(contentsOf: directoryURL.appendingPathComponent("source-\($0 + 1).png"))
            }
            let frames = try (0..<profile.frameCount).map {
                try Data(contentsOf: directoryURL.appendingPathComponent("frame-\($0 + 1).png"))
            }
            return CharacterAssets(profile: profile, sources: sources, frames: frames)
        } catch {
            throw CharacterStoreError.unreadableAssets
        }
    }
}
