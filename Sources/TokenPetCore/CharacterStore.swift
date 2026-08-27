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

public protocol CharacterStoreCommitBoundary: Sendable {
    func replaceItem(at targetURL: URL, withStagingItemAt stagingURL: URL, backupItemURL: URL) throws
    func removeOldBackup(at backupURL: URL) throws
}

private final class FileManagerCommitBoundary: @unchecked Sendable, CharacterStoreCommitBoundary {
    private let fileManager = FileManager.default

    func replaceItem(at targetURL: URL, withStagingItemAt stagingURL: URL, backupItemURL: URL) throws {
        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(
                targetURL,
                withItemAt: stagingURL,
                backupItemName: backupItemURL.lastPathComponent,
                options: [.withoutDeletingBackupItem]
            )
        } else {
            try fileManager.moveItem(at: stagingURL, to: targetURL)
        }
    }

    func removeOldBackup(at backupURL: URL) throws {
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        try fileManager.removeItem(at: backupURL)
    }
}

public final class CharacterStore: @unchecked Sendable {
    public static let builtInCharacterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let rootURL: URL
    private let defaults: UserDefaults
    private let commitBoundary: any CharacterStoreCommitBoundary
    private let fileManager = FileManager.default
    private let selectedCharacterIDKey = "TokenPet.selectedCharacterID"

    public init(rootURL: URL, defaults: UserDefaults) {
        self.rootURL = rootURL.standardizedFileURL
        self.defaults = defaults
        self.commitBoundary = FileManagerCommitBoundary()
    }

    public init(rootURL: URL, defaults: UserDefaults, commitBoundary: any CharacterStoreCommitBoundary) {
        self.rootURL = rootURL.standardizedFileURL
        self.defaults = defaults
        self.commitBoundary = commitBoundary
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
            let root = try checkedRoot(createIfMissing: false)
            removeOrphanedBackups(in: root)
            let entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
            let profiles = entries.compactMap { url -> CharacterProfile? in
                guard let id = UUID(uuidString: url.lastPathComponent), id != Self.builtInCharacterID else {
                    return nil
                }
                return try? readAssets(at: url, expectedID: id, root: root).profile
            }
            return profiles.sorted {
                let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
                if nameOrder == .orderedSame { return $0.id.uuidString < $1.id.uuidString }
                return nameOrder == .orderedAscending
            }
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    public func load(id: UUID) throws -> CharacterAssets {
        guard id != Self.builtInCharacterID else { throw CharacterStoreError.reservedBuiltInCharacter }
        guard fileManager.fileExists(atPath: rootURL.path) else { throw CharacterStoreError.notFound }
        do {
            let root = try checkedRoot(createIfMissing: false)
            return try readAssets(at: directoryURL(for: id, root: root), expectedID: id, root: root)
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.unreadableAssets
        }
    }

    public func save(_ assets: CharacterAssets) throws {
        guard assets.profile.id != Self.builtInCharacterID else { throw CharacterStoreError.reservedBuiltInCharacter }
        guard assets.sources.count == assets.profile.frameCount, assets.frames.count == assets.profile.frameCount else {
            throw CharacterStoreError.invalidAssetCount
        }

        let existingProfiles = try list().filter { $0.id != assets.profile.id }
        let validationErrors = CharacterProfileValidator.validate(assets.profile, existingNames: existingProfiles.map(\.name))
        guard validationErrors.isEmpty else { throw CharacterStoreError.invalidProfile(validationErrors) }

        do {
            let root = try checkedRoot(createIfMissing: true)
            removeOrphanedBackups(in: root)
            let targetURL = directoryURL(for: assets.profile.id, root: root)
            if fileManager.fileExists(atPath: targetURL.path) {
                try checkedProfileDirectory(targetURL, inside: root)
            }

            let stagingURL = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
            var stagingNeedsCleanup = true
            defer {
                if stagingNeedsCleanup { try? fileManager.removeItem(at: stagingURL) }
            }
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            try write(assets, to: stagingURL)
            guard try readAssets(at: stagingURL, expectedID: assets.profile.id, root: root) == assets else {
                throw CharacterStoreError.persistenceFailed
            }

            let targetExisted = fileManager.fileExists(atPath: targetURL.path)
            let backupURL = root.appendingPathComponent(".backup-\(assets.profile.id.uuidString)-\(UUID().uuidString)", isDirectory: true)
            try commitBoundary.replaceItem(at: targetURL, withStagingItemAt: stagingURL, backupItemURL: backupURL)
            stagingNeedsCleanup = false
            if targetExisted { try? commitBoundary.removeOldBackup(at: backupURL) }
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    public func delete(id: UUID) throws {
        guard id != Self.builtInCharacterID else { throw CharacterStoreError.reservedBuiltInCharacter }
        guard fileManager.fileExists(atPath: rootURL.path) else { throw CharacterStoreError.notFound }
        do {
            let root = try checkedRoot(createIfMissing: false)
            let targetURL = directoryURL(for: id, root: root)
            try checkedProfileDirectory(targetURL, inside: root)
            try fileManager.removeItem(at: targetURL)
            if selectedCharacterID == id { selectedCharacterID = nil }
        } catch let error as CharacterStoreError {
            throw error
        } catch {
            throw CharacterStoreError.persistenceFailed
        }
    }

    private func checkedRoot(createIfMissing: Bool) throws -> URL {
        if !fileManager.fileExists(atPath: rootURL.path) {
            guard createIfMissing else { throw CharacterStoreError.notFound }
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CharacterStoreError.persistenceFailed
        }
        return rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func directoryURL(for id: UUID, root: URL) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func write(_ assets: CharacterAssets, to directoryURL: URL) throws {
        try JSONEncoder().encode(assets.profile).write(to: directoryURL.appendingPathComponent("profile.json"), options: .atomic)
        for index in assets.sources.indices {
            try assets.sources[index].write(to: directoryURL.appendingPathComponent("source-\(index + 1).png"), options: .atomic)
        }
        for index in assets.frames.indices {
            try assets.frames[index].write(to: directoryURL.appendingPathComponent("frame-\(index + 1).png"), options: .atomic)
        }
    }

    private func readAssets(at directoryURL: URL, expectedID: UUID, root: URL) throws -> CharacterAssets {
        try checkedProfileDirectory(directoryURL, inside: root)
        let profileURL = directoryURL.appendingPathComponent("profile.json")
        guard let profile = try? JSONDecoder().decode(CharacterProfile.self, from: readRegularFile(profileURL, inside: directoryURL)),
              profile.id == expectedID,
              profile.id != Self.builtInCharacterID,
              CharacterProfileValidator.validate(profile, existingNames: []).isEmpty
        else { throw CharacterStoreError.unreadableAssets }

        let requiredNames = Set(
            ["profile.json"]
                + (1...profile.frameCount).map { "source-\($0).png" }
                + (1...profile.frameCount).map { "frame-\($0).png" }
        )
        guard Set(try fileManager.contentsOfDirectory(atPath: directoryURL.path)) == requiredNames else {
            throw CharacterStoreError.unreadableAssets
        }

        do {
            let sources = try (1...profile.frameCount).map {
                try readRegularFile(directoryURL.appendingPathComponent("source-\($0).png"), inside: directoryURL)
            }
            let frames = try (1...profile.frameCount).map {
                try readRegularFile(directoryURL.appendingPathComponent("frame-\($0).png"), inside: directoryURL)
            }
            return CharacterAssets(profile: profile, sources: sources, frames: frames)
        } catch {
            throw CharacterStoreError.unreadableAssets
        }
    }

    private func checkedProfileDirectory(_ directoryURL: URL, inside root: URL) throws {
        guard isInside(directoryURL, root), !isSymbolicLink(directoryURL) else {
            throw CharacterStoreError.unreadableAssets
        }
        let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CharacterStoreError.unreadableAssets }
    }

    private func readRegularFile(_ fileURL: URL, inside directoryURL: URL) throws -> Data {
        guard isInside(fileURL, directoryURL), !isSymbolicLink(fileURL) else {
            throw CharacterStoreError.unreadableAssets
        }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw CharacterStoreError.unreadableAssets }
        return try Data(contentsOf: fileURL)
    }

    private func isInside(_ candidate: URL, _ container: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let containerPath = container.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath.hasPrefix(containerPath + "/")
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func removeOrphanedBackups(in root: URL) {
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return
        }
        for entry in entries where entry.lastPathComponent.hasPrefix(".backup-") && !isSymbolicLink(entry) {
            try? fileManager.removeItem(at: entry)
        }
    }
}
