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

private func withStore(_ body: (CharacterStore, URL) throws -> Void) rethrows {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "TokenPetCharacterStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }
    try body(CharacterStore(rootURL: root, defaults: defaults), root)
}

private func testSavesLoadsListsAndClearsSelection() throws {
    let runner = TestRunner()
    try withStore { store, root in
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
    try withStore { store, root in
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

private func testRejectsReservedBuiltInProfileMutations() {
    let runner = TestRunner()
    withStore { store, _ in
        let profile = makeProfile(id: CharacterStore.builtInCharacterID)
        do {
            try store.save(makeAssets(profile: profile))
            runner.expectTrue(false, "reserved profile save rejected")
        } catch {
            runner.expectTrue(true, "reserved profile save rejected")
        }
        do {
            try store.delete(id: CharacterStore.builtInCharacterID)
            runner.expectTrue(false, "reserved profile delete rejected")
        } catch {
            runner.expectTrue(true, "reserved profile delete rejected")
        }
    }
    if runner.failures > 0 { exit(1) }
}

do {
    try testSavesLoadsListsAndClearsSelection()
    try testSkipsCorruptProfilesAndPreservesExistingAssetsOnRejectedReplacement()
    testRejectsReservedBuiltInProfileMutations()
    print("PASS: TokenPetCharacterStoreTests")
} catch {
    print("FAIL: unexpected error — \(error)")
    exit(1)
}
