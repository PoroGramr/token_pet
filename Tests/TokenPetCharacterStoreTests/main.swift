import Darwin
import Foundation
import TokenPetCore

private final class TestRunner {
    private(set) var failures = 0

    func expectEqual<T: Equatable>(
        _ actual: @autoclosure () throws -> T,
        _ expected: T,
        _ name: String
    ) {
        do {
            let value = try actual()
            if value != expected {
                failures += 1
                print("FAIL: \(name) — expected \(expected), got \(value)")
            }
        } catch {
            failures += 1
            print("FAIL: \(name) — threw \(error)")
        }
    }

    func expectTrue(_ condition: @autoclosure () -> Bool, _ name: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(name)")
        }
    }
}

private enum InjectedCommitError: Error {
    case replacement
    case cleanup
}

private final class ReplacementFailureBoundary: @unchecked Sendable, CharacterStoreCommitBoundary {
    func replaceItem(at targetURL: URL, withStagingItemAt stagingURL: URL, backupItemURL: URL) throws {
        throw InjectedCommitError.replacement
    }

    func removeOldBackup(at backupURL: URL) throws {
        try FileManager.default.removeItem(at: backupURL)
    }
}

private final class CleanupFailureBoundary: @unchecked Sendable, CharacterStoreCommitBoundary {
    func replaceItem(at targetURL: URL, withStagingItemAt stagingURL: URL, backupItemURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            targetURL,
            withItemAt: stagingURL,
            backupItemName: backupItemURL.lastPathComponent,
            options: [.withoutDeletingBackupItem]
        )
    }

    func removeOldBackup(at backupURL: URL) throws {
        throw InjectedCommitError.cleanup
    }
}

private func makeProfile(id: UUID = UUID(), name: String = "Mochi") -> CharacterProfile {
    CharacterProfile(
        id: id,
        name: name,
        frameCount: 3,
        frameOrder: [0, 1, 2],
        removesLightBackground: true,
        percentPosition: NormalizedPoint(x: 0.5, y: 0.6),
        percentFontSize: 22,
        framesPerSecond: 3,
        schemaVersion: 1
    )
}

private func makeAssets(profile: CharacterProfile) -> CharacterAssets {
    let sourceFrames = [Data("source-0".utf8), Data("source-1".utf8), Data("source-2".utf8)]
    let displayFrames = [Data("frame-0".utf8), Data("frame-1".utf8), Data("frame-2".utf8)]
    return CharacterAssets(profile: profile, sources: sourceFrames, frames: displayFrames)
}

private func withStore(_ body: (CharacterStore, URL, UserDefaults) throws -> Void) rethrows {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "TokenPetCharacterStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
    try body(CharacterStore(rootURL: root, defaults: defaults), root, defaults)
}

private func expectThrows(_ operation: () throws -> Void, _ name: String, runner: TestRunner) {
    do {
        try operation()
        runner.expectTrue(false, name)
    } catch {
        runner.expectTrue(true, name)
    }
}

private func onDiskSnapshot(_ directory: URL, frameCount: Int) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for filename in ["profile.json"]
        + (1...frameCount).map({ "source-\($0).png" })
        + (1...frameCount).map({ "frame-\($0).png" }) {
        result[filename] = try Data(contentsOf: directory.appendingPathComponent(filename))
    }
    return result
}

private func writeAssets(_ assets: CharacterAssets, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(assets.profile).write(to: directory.appendingPathComponent("profile.json"))
    for index in assets.sources.indices {
        try assets.sources[index].write(to: directory.appendingPathComponent("source-\(index + 1).png"))
    }
    for index in assets.frames.indices {
        try assets.frames[index].write(to: directory.appendingPathComponent("frame-\(index + 1).png"))
    }
}

private func testSavesLoadsListsAndClearsSelection() throws {
    let runner = TestRunner()
    try withStore { store, root, _ in
        let profile = makeProfile()
        let assets = makeAssets(profile: profile)

        try store.save(assets)

        runner.expectEqual(try store.list().map(\.id), [profile.id], "saved profile listed")
        runner.expectEqual(try store.load(id: profile.id), assets, "saved assets load")
        let characterDirectory = root.appendingPathComponent(profile.id.uuidString)
        runner.expectTrue(
            FileManager.default.fileExists(atPath: characterDirectory.appendingPathComponent("source-1.png").path),
            "sources use one-based filenames"
        )
        store.selectedCharacterID = profile.id
        try store.delete(id: profile.id)
        runner.expectEqual(store.selectedCharacterID, nil, "deleting selected profile clears selection")
    }
    if runner.failures > 0 { exit(1) }
}

private func testSkipsCorruptProfilesAndPreservesExistingAssetsOnRejectedReplacement() throws {
    let runner = TestRunner()
    try withStore { store, root, _ in
        let profile = makeProfile()
        let originalAssets = makeAssets(profile: profile)
        try store.save(originalAssets)

        let corruptDirectory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: corruptDirectory.appendingPathComponent("profile.json"))
        runner.expectEqual(try store.list().map(\.id), [profile.id], "corrupt profile skipped")

        var invalidReplacement = originalAssets
        invalidReplacement.frames.removeLast()
        do {
            try store.save(invalidReplacement)
            runner.expectTrue(false, "mismatched frame count rejected")
        } catch {
            runner.expectTrue(true, "mismatched frame count rejected")
        }
        runner.expectEqual(try store.load(id: profile.id), originalAssets, "rejected replacement preserves assets")
    }
    if runner.failures > 0 { exit(1) }
}

private func testRejectsReservedBuiltInProfileMutationsAndLoads() throws {
    let runner = TestRunner()
    try withStore { store, root, _ in
        let profile = makeProfile(id: CharacterStore.builtInCharacterID)
        let assets = makeAssets(profile: profile)
        expectThrows({ try store.save(assets) }, "reserved profile save rejected", runner: runner)
        expectThrows({ try store.delete(id: CharacterStore.builtInCharacterID) }, "reserved profile delete rejected", runner: runner)
        try writeAssets(assets, to: root.appendingPathComponent(profile.id.uuidString))
        runner.expectEqual(try store.list(), [], "reserved profile skipped from list")
        expectThrows({ _ = try store.load(id: profile.id) }, "reserved profile load rejected", runner: runner)
    }
    if runner.failures > 0 { exit(1) }
}

private func testRejectsExtraFilesAndSymlinks() throws {
    let runner = TestRunner()
    try withStore { store, root, defaults in
        let profile = makeProfile()
        let assets = makeAssets(profile: profile)
        try store.save(assets)
        let profileDirectory = root.appendingPathComponent(profile.id.uuidString)

        try Data("extra".utf8).write(to: profileDirectory.appendingPathComponent("extra.png"))
        runner.expectEqual(try store.list(), [], "extra frame file skips profile")
        expectThrows({ _ = try store.load(id: profile.id) }, "extra frame file rejects load", runner: runner)
        try FileManager.default.removeItem(at: profileDirectory.appendingPathComponent("extra.png"))

        let externalFrame = root.appendingPathComponent("external-frame.png")
        try FileManager.default.moveItem(at: profileDirectory.appendingPathComponent("frame-1.png"), to: externalFrame)
        try FileManager.default.createSymbolicLink(at: profileDirectory.appendingPathComponent("frame-1.png"), withDestinationURL: externalFrame)
        runner.expectEqual(try store.list(), [], "frame symlink skips profile")
        expectThrows({ _ = try store.load(id: profile.id) }, "frame symlink rejects load", runner: runner)
        try FileManager.default.removeItem(at: profileDirectory)

        let outsideDirectory = root.appendingPathComponent("outside-directory")
        try writeAssets(assets, to: outsideDirectory)
        try FileManager.default.createSymbolicLink(at: profileDirectory, withDestinationURL: outsideDirectory)
        runner.expectEqual(try store.list(), [], "UUID symlink skips profile")
        expectThrows({ _ = try store.load(id: profile.id) }, "UUID symlink rejects load", runner: runner)
        expectThrows({ try store.delete(id: profile.id) }, "UUID symlink rejects delete", runner: runner)
        expectThrows({ try store.save(assets) }, "UUID symlink rejects save", runner: runner)

        let linkedRoot = root.deletingLastPathComponent().appendingPathComponent("linked-root-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        let linkedStore = CharacterStore(rootURL: linkedRoot, defaults: defaults)
        expectThrows({ _ = try linkedStore.list() }, "symlink root rejects list", runner: runner)
        expectThrows({ try linkedStore.save(makeAssets(profile: makeProfile())) }, "symlink root rejects save", runner: runner)
    }
    if runner.failures > 0 { exit(1) }
}

private func testCommitFailurePreservesExistingTargetAndCleansStaging() throws {
    let runner = TestRunner()
    try withStore { store, root, defaults in
        let profile = makeProfile()
        let original = makeAssets(profile: profile)
        try store.save(original)
        let target = root.appendingPathComponent(profile.id.uuidString)
        let before = try onDiskSnapshot(target, frameCount: profile.frameCount)

        var replacement = original
        replacement.frames[0] = Data("replacement-frame".utf8)
        let failingStore = CharacterStore(rootURL: root, defaults: defaults, commitBoundary: ReplacementFailureBoundary())
        expectThrows({ try failingStore.save(replacement) }, "injected commit failure rejected", runner: runner)

        runner.expectEqual(try onDiskSnapshot(target, frameCount: profile.frameCount), before, "commit failure preserves target bytes")
        let rootEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        runner.expectTrue(!rootEntries.contains(where: { $0.hasPrefix(".staging-") }), "commit failure cleans staging")
    }
    if runner.failures > 0 { exit(1) }
}

private func testCleanupFailureKeepsCommittedReplacement() throws {
    let runner = TestRunner()
    try withStore { store, root, defaults in
        let profile = makeProfile()
        let original = makeAssets(profile: profile)
        try store.save(original)

        var replacement = original
        replacement.sources[0] = Data("replacement-source".utf8)
        let cleanupFailureStore = CharacterStore(rootURL: root, defaults: defaults, commitBoundary: CleanupFailureBoundary())
        try cleanupFailureStore.save(replacement)

        runner.expectEqual(try store.load(id: profile.id), replacement, "cleanup failure keeps committed replacement")
        let rootEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        runner.expectTrue(rootEntries.contains(where: { $0.hasPrefix(".backup-") }), "cleanup failure leaves retryable backup")
    }
    if runner.failures > 0 { exit(1) }
}

do {
    try testSavesLoadsListsAndClearsSelection()
    try testSkipsCorruptProfilesAndPreservesExistingAssetsOnRejectedReplacement()
    try testRejectsReservedBuiltInProfileMutationsAndLoads()
    try testRejectsExtraFilesAndSymlinks()
    try testCommitFailurePreservesExistingTargetAndCleansStaging()
    try testCleanupFailureKeepsCommittedReplacement()
    print("PASS: TokenPetCharacterStoreTests")
} catch {
    print("FAIL: unexpected error — \(error)")
    exit(1)
}
