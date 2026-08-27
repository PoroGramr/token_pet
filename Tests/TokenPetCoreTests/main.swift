import Darwin
import CoreGraphics
import Foundation
import ImageIO
import TokenPetCore
import UniformTypeIdentifiers

private final class TestRunner {
    var failures = 0

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

private let runner = TestRunner()

private struct FakeCredentialDataReader: CredentialDataReading {
    let dataByService: [String: Data]

    func readCredentialData(service: String) throws -> Data? {
        dataByService[service]
    }
}

@MainActor
private func testDecodesFiveHourUsageAndCalculatesRemainingPercent() throws {
    let data = Data(#"{"five_hour":{"utilization":28.4,"resets_at":"2026-08-27T08:00:00Z"}}"#.utf8)
    let response = try JSONDecoder.tokenPet.decode(UsageResponse.self, from: data)

    runner.expectEqual(response.fiveHour?.remainingPercent, 72, "remaining percent")
    runner.expectEqual(
        response.fiveHour?.resetsAt,
        ISO8601DateFormatter().date(from: "2026-08-27T08:00:00Z"),
        "reset timestamp"
    )
}

@MainActor
private func testClampsRemainingPercent() {
    let cases: [(Double, Int)] = [(-4, 100), (0, 100), (99.6, 0), (120, 0)]
    for (utilization, expected) in cases {
        runner.expectEqual(
            UsageWindow(utilization: utilization, resetsAt: nil).remainingPercent,
            expected,
            "clamp utilization \(utilization)"
        )
    }
}

@MainActor
private func testBuildsAuthenticatedUsageRequest() throws {
    let request = try UsageRequestFactory.make(accessToken: "secret-token")

    runner.expectEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage", "usage URL")
    runner.expectEqual(request.httpMethod, "GET", "usage method")
    runner.expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token", "authorization header")
    runner.expectEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20", "beta header")
}

@MainActor
private func testParsesUsageAndRecognizesHTTPFailures() throws {
    let body = Data(#"{"five_hour":{"utilization":40,"resets_at":null}}"#.utf8)
    let snapshot = try UsageResponseParser.parse(data: body, statusCode: 200, fetchedAt: Date(timeIntervalSince1970: 10))
    runner.expectEqual(snapshot.remainingPercent, 60, "parsed snapshot percent")
    runner.expectEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 10), "snapshot fetch time")

    do {
        _ = try UsageResponseParser.parse(data: Data(), statusCode: 401, fetchedAt: .distantPast)
        runner.expectTrue(false, "401 must throw unauthorized")
    } catch let error as UsageClientError {
        runner.expectEqual(error, .unauthorized, "401 error")
    }

    do {
        _ = try UsageResponseParser.parse(data: Data(), statusCode: 429, fetchedAt: .distantPast)
        runner.expectTrue(false, "429 must throw rate limited")
    } catch let error as UsageClientError {
        runner.expectEqual(error, .rateLimited(retryAfter: nil), "429 error")
    }
}

@MainActor
private func testKeepsLastValueWhenRefreshFails() {
    var state = UsageStateMachine()
    let snapshot = UsageSnapshot(remainingPercent: 77, resetsAt: nil, fetchedAt: Date(timeIntervalSince1970: 10))

    runner.expectEqual(state.receive(snapshot), .available(snapshot, isStale: false), "fresh state")
    runner.expectEqual(state.fail(.network), .available(snapshot, isStale: true), "stale cached state")

    var emptyState = UsageStateMachine()
    runner.expectEqual(emptyState.fail(.unauthorized), .unauthenticated, "unauthenticated without cache")
    var incompatibleState = UsageStateMachine()
    runner.expectEqual(incompatibleState.fail(.incompatibleResponse), .failed("API 응답 형식이 변경되었습니다"), "incompatible response")
    var lockedState = UsageStateMachine()
    runner.expectEqual(lockedState.fail(.keychainLocked), .failed("Mac 로그인 키체인이 잠겨 있습니다"), "locked keychain")
    var deniedState = UsageStateMachine()
    runner.expectEqual(deniedState.fail(.keychainDenied), .failed("Keychain 접근이 거부되었습니다"), "denied keychain")
}

@MainActor
private func testDecodesClaudeCodeCredentialEnvelope() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"access","refreshToken":"refresh","expiresAt":1787800000000,"scopes":["user:profile"],"subscriptionType":"max"}}"#.utf8)

    let credentials = try ClaudeCredentialsCodec.decode(data)

    runner.expectEqual(credentials.accessToken, "access", "credential access token")
    runner.expectEqual(credentials.expiresAtMilliseconds, 1_787_800_000_000, "credential expiry")
}

@MainActor
private func testLoadsLegacyCredentialThroughAuthorizedSecurityToolFallback() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"fallback-access","expiresAt":1787800000000}}"#.utf8)
    let store = SecurityToolCredentialStore(
        services: ["Claude Code-credentials-namespaced", "Claude Code-credentials"],
        reader: FakeCredentialDataReader(dataByService: ["Claude Code-credentials": data])
    )

    runner.expectEqual(try store.loadAccessToken(), "fallback-access", "security tool fallback access token")
}

@MainActor
private func testSecurityToolFallbackRequiresExplicitConsentAndNeverRunsAfterCancel() {
    runner.expectEqual(
        CredentialFallbackPolicy.shouldUseSecurityTool(for: .keychainDenied, userAllowed: false),
        false,
        "denied keychain without fallback consent"
    )
    runner.expectEqual(
        CredentialFallbackPolicy.shouldUseSecurityTool(for: .keychainDenied, userAllowed: true),
        true,
        "denied keychain with fallback consent"
    )
    runner.expectEqual(
        CredentialFallbackPolicy.shouldUseSecurityTool(for: .keychainCanceled, userAllowed: true),
        false,
        "canceled keychain must never fall back"
    )
    runner.expectEqual(
        CredentialFallbackPolicy.shouldUseSecurityTool(for: .keychain(statusCode: -1), userAllowed: true),
        false,
        "unknown keychain error must never fall back"
    )
}

private func alphaValue(in image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .none
    context.translateBy(x: CGFloat(-x), y: CGFloat(-(image.height - y - 1)))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixel[3]
}

@MainActor
private func testDefinesPingPongAnimationSequence() {
    runner.expectEqual(FrameSequence.indices, [1, 2, 3, 4, 3, 2], "animation frame order")
    runner.expectEqual(FrameSequence.framesPerSecond, 3, "animation speed")
}

@MainActor
private func testCharacterProfileAndPercentLayoutContracts() throws {
    let threeFrame = CharacterProfile(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: "Cat",
        frameCount: 3,
        frameOrder: [0, 1, 2],
        removesLightBackground: false,
        percentPosition: NormalizedPoint(x: 0.5, y: 0.58),
        percentFontSize: 22,
        framesPerSecond: 3,
        schemaVersion: 1
    )
    runner.expectEqual(FrameSequence.indices(frameCount: 3), [0, 1, 2, 1], "3-frame ping-pong")
    runner.expectEqual(FrameSequence.indices(frameCount: 4), [0, 1, 2, 3, 2, 1], "built-in 4-frame ping-pong")
    runner.expectEqual(
        PercentLayout.textRect(
            containerSize: CGSize(width: 120, height: 120),
            position: NormalizedPoint(x: 0.5, y: 0.5),
            fontSize: 10,
            measuredTextSize: CGSize(width: 20, height: 10)
        ),
        CGRect(x: 50, y: 55, width: 20, height: 10),
        "10pt text is centered at its normalized position"
    )
    runner.expectEqual(
        PercentLayout.textRect(
            containerSize: CGSize(width: 120, height: 120),
            position: NormalizedPoint(x: 0.5, y: 0.5),
            fontSize: 36,
            measuredTextSize: CGSize(width: 70, height: 36)
        ),
        CGRect(x: 25, y: 42, width: 70, height: 36),
        "36pt text is centered at its normalized position"
    )
    runner.expectEqual(
        PercentLayout.textRect(
            containerSize: CGSize(width: 120, height: 120),
            position: NormalizedPoint(x: -0.5, y: 2),
            fontSize: 20,
            measuredTextSize: CGSize(width: 40, height: 20)
        ),
        CGRect(x: 0, y: 100, width: 40, height: 20),
        "text rect is clamped inside its container"
    )
    runner.expectEqual(try JSONDecoder().decode(CharacterProfile.self, from: JSONEncoder().encode(threeFrame)), threeFrame, "profile round trip")
    runner.expectEqual(PercentLayout.clampedPosition(NormalizedPoint(x: 2, y: -1)), NormalizedPoint(x: 1, y: 0), "position clamp")
    runner.expectTrue(CharacterProfileValidator.validate(threeFrame, existingNames: []).isEmpty, "valid profile")

    var duplicate = threeFrame
    duplicate.name = " cat "
    runner.expectTrue(!CharacterProfileValidator.validate(duplicate, existingNames: ["CAT"]).isEmpty, "duplicate name rejected")
    var invalidFrames = threeFrame
    invalidFrames.frameCount = 5
    runner.expectTrue(!CharacterProfileValidator.validate(invalidFrames, existingNames: []).isEmpty, "five user frames rejected")

    var negativeFrameCount = threeFrame
    negativeFrameCount.frameCount = -1
    runner.expectEqual(
        CharacterProfileValidator.validate(negativeFrameCount, existingNames: []),
        ["frameCount", "frameOrder"],
        "negative frame count returns validation errors without trapping"
    )

    var enormousFrameCount = threeFrame
    enormousFrameCount.frameCount = .max
    let enormousJSON = try JSONEncoder().encode(enormousFrameCount)
    let decodedEnormous = try JSONDecoder().decode(CharacterProfile.self, from: enormousJSON)
    runner.expectEqual(
        CharacterProfileValidator.validate(decodedEnormous, existingNames: []),
        ["frameCount", "frameOrder"],
        "Int.max frame count JSON returns validation errors without allocating"
    )

    var reordered = threeFrame
    reordered.frameOrder = [2, 0, 1]
    runner.expectTrue(CharacterProfileValidator.validate(reordered, existingNames: []).isEmpty, "valid reordered permutation accepted")
    var duplicateIndex = threeFrame
    duplicateIndex.frameOrder = [0, 1, 1]
    runner.expectTrue(!CharacterProfileValidator.validate(duplicateIndex, existingNames: []).isEmpty, "duplicate frame index rejected")
    var missingIndex = threeFrame
    missingIndex.frameOrder = [0, 1, 3]
    runner.expectTrue(!CharacterProfileValidator.validate(missingIndex, existingNames: []).isEmpty, "missing frame index rejected")

    var shortName = threeFrame
    shortName.name = "   "
    runner.expectTrue(!CharacterProfileValidator.validate(shortName, existingNames: []).isEmpty, "blank name rejected")
    var invalidPosition = threeFrame
    invalidPosition.percentPosition = NormalizedPoint(x: 1.01, y: 0)
    runner.expectTrue(!CharacterProfileValidator.validate(invalidPosition, existingNames: []).isEmpty, "out of range position rejected")
    var minimumFont = threeFrame
    minimumFont.percentFontSize = 10
    runner.expectTrue(CharacterProfileValidator.validate(minimumFont, existingNames: []).isEmpty, "minimum font accepted")
    var maximumFont = threeFrame
    maximumFont.percentFontSize = 36
    runner.expectTrue(CharacterProfileValidator.validate(maximumFont, existingNames: []).isEmpty, "maximum font accepted")
    var invalidFPS = threeFrame
    invalidFPS.framesPerSecond = 2
    runner.expectTrue(!CharacterProfileValidator.validate(invalidFPS, existingNames: []).isEmpty, "invalid FPS rejected")
    var invalidSchema = threeFrame
    invalidSchema.schemaVersion = 2
    runner.expectTrue(!CharacterProfileValidator.validate(invalidSchema, existingNames: []).isEmpty, "invalid schema rejected")
}

@MainActor
private func testKeepsPercentPositionsWithTheirCharacterFrames() throws {
    let first = NormalizedPoint(x: 0.2, y: 0.3)
    let second = NormalizedPoint(x: 0.5, y: 0.6)
    let third = NormalizedPoint(x: 0.8, y: 0.7)
    let legacy = CharacterProfile(
        id: UUID(), name: "Legacy", frameCount: 3, frameOrder: [0, 1, 2],
        removesLightBackground: false, percentPosition: first,
        percentFontSize: 22, framesPerSecond: 3, schemaVersion: 1
    )
    runner.expectEqual(
        legacy.resolvedFramePercentPositions,
        [first, first, first],
        "legacy percent position is copied to every frame"
    )

    var profile = legacy
    profile.framePercentPositions = [first, second, third]
    runner.expectTrue(
        CharacterProfileValidator.validate(profile, existingNames: []).isEmpty,
        "three frame positions are valid"
    )
    runner.expectEqual(
        FramePercentPositionMapper.ordered(
            positions: profile.resolvedFramePercentPositions,
            frameOrder: [2, 0, 1]
        ),
        [third, first, second],
        "runtime positions use the same order as runtime frames"
    )

    var wrongCount = profile
    wrongCount.framePercentPositions = [first, second]
    runner.expectTrue(
        CharacterProfileValidator.validate(wrongCount, existingNames: []).contains("framePercentPositions"),
        "wrong position count is rejected"
    )
    var outOfRange = profile
    outOfRange.framePercentPositions = [first, second, NormalizedPoint(x: 1.1, y: 0.5)]
    runner.expectTrue(
        CharacterProfileValidator.validate(outOfRange, existingNames: []).contains("framePercentPositions"),
        "out of range frame position is rejected"
    )
}

@MainActor
private func testBuildsSafeCharacterMenuPresentation() {
    let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let catID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let invalidSelectedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let builtIn = CharacterProfile(
        id: builtInID,
        name: "기본 캐릭터",
        frameCount: 4,
        frameOrder: [0, 1, 2, 3],
        removesLightBackground: true,
        percentPosition: NormalizedPoint(x: 0.5, y: 0.5),
        percentFontSize: 22,
        framesPerSecond: 3,
        schemaVersion: 1
    )
    let cat = CharacterProfile(
        id: catID,
        name: "Cat",
        frameCount: 3,
        frameOrder: [0, 1, 2],
        removesLightBackground: false,
        percentPosition: NormalizedPoint(x: 0.5, y: 0.5),
        percentFontSize: 20,
        framesPerSecond: 3,
        schemaVersion: 1
    )

    let selected = CharacterMenuPresentation.make(
        profiles: [cat, builtIn],
        builtInID: builtInID,
        selectedID: catID
    )
    runner.expectEqual(selected.entries.map(\.id), [builtInID, catID], "built-in menu entry appears first")
    runner.expectEqual(selected.entries.map(\.isSelected), [false, true], "valid selected character is checked")
    runner.expectEqual(selected.selectedID, catID, "valid selected character is retained")
    runner.expectEqual(selected.didFallbackToBuiltIn, false, "valid selection does not fall back")

    let fallback = CharacterMenuPresentation.make(
        profiles: [cat, builtIn],
        builtInID: builtInID,
        selectedID: invalidSelectedID
    )
    runner.expectEqual(fallback.entries.map(\.isSelected), [true, false], "missing selected character checks built-in")
    runner.expectEqual(fallback.selectedID, builtInID, "missing selected character resolves to built-in")
    runner.expectEqual(fallback.didFallbackToBuiltIn, true, "missing selected character reports fallback")
}

private enum CharacterMenuCatalogFixtureError: Error {
    case unavailable
}

private final class FlakyCharacterMenuCatalog: @unchecked Sendable, CharacterMenuCatalog {
    var selectedCharacterID: UUID?
    var profiles: [CharacterProfile]
    var failuresRemaining: Int

    init(selectedCharacterID: UUID?, profiles: [CharacterProfile], failuresRemaining: Int) {
        self.selectedCharacterID = selectedCharacterID
        self.profiles = profiles
        self.failuresRemaining = failuresRemaining
    }

    func list() throws -> [CharacterProfile] {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CharacterMenuCatalogFixtureError.unavailable
        }
        return profiles
    }
}

@MainActor
private func testPreservesCharacterSelectionAcrossTransientCatalogFailure() throws {
    let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let catID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let builtIn = CharacterProfile(
        id: builtInID, name: "기본 캐릭터", frameCount: 4, frameOrder: [0, 1, 2, 3],
        removesLightBackground: true, percentPosition: .init(x: 0.5, y: 0.5),
        percentFontSize: 22, framesPerSecond: 3, schemaVersion: 1
    )
    let cat = CharacterProfile(
        id: catID, name: "Cat", frameCount: 3, frameOrder: [0, 1, 2],
        removesLightBackground: false, percentPosition: .init(x: 0.5, y: 0.5),
        percentFontSize: 20, framesPerSecond: 3, schemaVersion: 1
    )
    let catalog = FlakyCharacterMenuCatalog(
        selectedCharacterID: catID,
        profiles: [cat],
        failuresRemaining: 1
    )
    let resolver = CharacterMenuResolver(catalog: catalog, builtInProfile: builtIn)

    do {
        _ = try resolver.presentation()
        runner.expectTrue(false, "transient catalog failure must be propagated")
    } catch CharacterMenuCatalogFixtureError.unavailable {
        runner.expectEqual(catalog.selectedCharacterID, catID, "transient failure preserves selected ID")
    }

    let recovered = try resolver.presentation()
    runner.expectEqual(recovered.selectedID, catID, "successful retry restores selected menu entry")
    runner.expectEqual(catalog.selectedCharacterID, catID, "successful retry retains selected ID")

    catalog.profiles = []
    let missing = try resolver.presentation()
    runner.expectEqual(missing.didFallbackToBuiltIn, true, "successful listing detects genuinely missing selection")
    runner.expectEqual(catalog.selectedCharacterID, nil, "genuinely missing selection is cleared")
}

@MainActor
private func testDefinesCharacterMenuSiblingStructureAndRepresentedIDs() {
    let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let catID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let profiles = [
        CharacterProfile(
            id: builtInID, name: "기본 캐릭터", frameCount: 4, frameOrder: [0, 1, 2, 3],
            removesLightBackground: true, percentPosition: .init(x: 0.5, y: 0.5),
            percentFontSize: 22, framesPerSecond: 3, schemaVersion: 1
        ),
        CharacterProfile(
            id: catID, name: "Cat", frameCount: 3, frameOrder: [0, 1, 2],
            removesLightBackground: false, percentPosition: .init(x: 0.5, y: 0.5),
            percentFontSize: 20, framesPerSecond: 3, schemaVersion: 1
        )
    ]
    let snapshot = CharacterMenuPresentation.make(
        profiles: profiles,
        builtInID: builtInID,
        selectedID: catID
    )
    let structure = CharacterMenuStructureDescriptor.standard

    runner.expectEqual(
        structure.rootItems.map(\.role),
        [.characterSubmenu, .manageCharacters],
        "character and manager are sibling root items"
    )
    runner.expectEqual(
        structure.rootItems.map(\.title),
        ["캐릭터", "캐릭터 관리…"],
        "character sibling titles"
    )
    let submenuItems = structure.selectionItems(for: snapshot)
    runner.expectEqual(
        submenuItems.map(\.representedID),
        [builtInID.uuidString, catID.uuidString],
        "submenu represented IDs map to character UUIDs"
    )
    runner.expectEqual(
        submenuItems.contains { $0.title == "캐릭터 관리…" },
        false,
        "character submenu contains selection items only"
    )
}

@MainActor
private func testShowsCharacterRefreshErrorsInCurrentMenuOpening() {
    runner.expectEqual(
        CharacterMenuStatusPresentation.message(
            pendingError: nil,
            refreshNotice: .listUnavailable,
            usageMessage: "72% 남음"
        ),
        "캐릭터 목록을 불러오지 못했습니다",
        "catalog failure replaces usage status in current opening"
    )
    runner.expectEqual(
        CharacterMenuStatusPresentation.message(
            pendingError: nil,
            refreshNotice: .fallbackToBuiltIn,
            usageMessage: "72% 남음"
        ),
        "선택한 캐릭터를 불러오지 못해 기본 캐릭터로 돌아갔습니다",
        "fallback is visible in current opening"
    )
    runner.expectEqual(
        CharacterMenuStatusPresentation.message(
            pendingError: "로그인 오류",
            refreshNotice: .none,
            usageMessage: "72% 남음"
        ),
        "로그인 오류",
        "pending menu error remains visible without character error"
    )
    runner.expectEqual(
        CharacterMenuStatusPresentation.message(
            pendingError: nil,
            refreshNotice: .runtimeUnavailable,
            usageMessage: "72% 남음"
        ),
        "선택한 캐릭터를 표시하지 못했습니다",
        "runtime reconcile failure is visible in current opening"
    )
}

@MainActor
private func testReconcilesRuntimeDisplayWithoutLosingPersistedSelection() {
    let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let previousID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    let recoveredID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!

    let previousState = CharacterRuntimeSelectionState(
        displayedID: previousID,
        persistedSelectedID: previousID
    )
    let failedSelection = CharacterRuntimeReconciliation.afterSelectionAttemptFailed(current: previousState)
    runner.expectEqual(failedSelection.state, previousState, "failed selection preserves displayed and persisted IDs")
    runner.expectEqual(failedSelection.decision, .keepCurrent, "failed selection keeps current runtime")

    let temporaryBuiltIn = CharacterRuntimeSelectionState(
        displayedID: builtInID,
        persistedSelectedID: recoveredID
    )
    let recovered = CharacterRuntimeReconciliation.afterSuccessfulCatalog(
        current: temporaryBuiltIn,
        effectiveSelectedID: recoveredID,
        persistedSelectedID: recoveredID
    )
    runner.expectEqual(recovered.decision, .apply(recoveredID), "catalog recovery reapplies persisted user runtime")
    runner.expectEqual(recovered.state.persistedSelectedID, recoveredID, "catalog recovery preserves persisted user ID")

    let missing = CharacterRuntimeReconciliation.afterSuccessfulCatalog(
        current: CharacterRuntimeSelectionState(displayedID: previousID, persistedSelectedID: previousID),
        effectiveSelectedID: builtInID,
        persistedSelectedID: nil
    )
    runner.expectEqual(missing.decision, .apply(builtInID), "confirmed missing selection applies built-in runtime")
    runner.expectEqual(missing.state.persistedSelectedID, nil, "confirmed missing selection reflects cleanup")
}

@MainActor
private func testEditorRefreshRecoversPersistedSelectionAfterCatalogFailure() {
    let builtInID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let userID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

    let duringFailure = CharacterEditorSelectionReconciliation.resolve(
        currentSelectedID: builtInID,
        persistedSelectedID: userID,
        builtInID: builtInID,
        catalog: .unavailable
    )
    runner.expectEqual(duringFailure, builtInID, "editor catalog failure preserves current UI selection")

    let afterRecovery = CharacterEditorSelectionReconciliation.resolve(
        currentSelectedID: duringFailure,
        persistedSelectedID: userID,
        builtInID: builtInID,
        catalog: .available([builtInID, userID])
    )
    runner.expectEqual(afterRecovery, userID, "editor successful retry restores persisted user selection")
}

@MainActor
private func testEditorDiscardTransitionsPreserveDirtyDraftUntilReplacementLoads() {
    let currentID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
    let targetID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let current = CharacterEditorDraftState(selectedID: currentID, draftID: currentID, isDirty: true)

    let failedSwitch = CharacterEditorStateTransitions.afterSelectionAttempt(
        current: current,
        loadedSelection: nil
    )
    runner.expectEqual(failedSwitch, current, "failed target load preserves selected draft and dirty state")

    let successfulSwitch = CharacterEditorStateTransitions.afterSelectionAttempt(
        current: current,
        loadedSelection: .draft(targetID)
    )
    runner.expectEqual(
        successfulSwitch,
        CharacterEditorDraftState(selectedID: targetID, draftID: targetID, isDirty: false),
        "successful target load installs a clean draft"
    )

    let newDraft = CharacterEditorStateTransitions.afterCreatingDraft(current: current, newDraftID: targetID)
    runner.expectEqual(
        newDraft,
        CharacterEditorDraftState(selectedID: targetID, draftID: targetID, isDirty: true),
        "approved create path starts a new dirty draft"
    )

    let failedClose = CharacterEditorStateTransitions.afterCloseReload(current: current, reloaded: nil)
    runner.expectEqual(failedClose.state, current, "failed close reload preserves dirty draft")
    runner.expectEqual(failedClose.shouldClose, false, "failed close reload keeps window open")

    let cleanBuiltIn = CharacterEditorDraftState(
        selectedID: CharacterStore.builtInCharacterID,
        draftID: nil,
        isDirty: false
    )
    let successfulClose = CharacterEditorStateTransitions.afterCloseReload(current: current, reloaded: cleanBuiltIn)
    runner.expectEqual(successfulClose.state, cleanBuiltIn, "successful close reload installs clean snapshot")
    runner.expectEqual(successfulClose.shouldClose, true, "successful close reload permits close")
}

@MainActor
private func testRemovesConnectedCheckerboardBackgroundFromOpaqueFrames() throws {
    for path in ["img/2.png", "img/3.png"] {
        let image = try FrameImageProcessor.makeTransparentImage(from: Data(contentsOf: URL(fileURLWithPath: path)))
        runner.expectEqual(alphaValue(in: image, x: 0, y: 0), 0, "transparent corner for \(path)")
        runner.expectTrue(alphaValue(in: image, x: image.width / 2, y: image.height / 2) > 240, "opaque body for \(path)")
    }
}

@MainActor
private func testPreservesExistingTransparency() throws {
    let image = try FrameImageProcessor.makeTransparentImage(from: Data(contentsOf: URL(fileURLWithPath: "img/1.png")))
    runner.expectEqual(alphaValue(in: image, x: 0, y: 0), 0, "existing transparent corner")
    runner.expectTrue(alphaValue(in: image, x: image.width / 2, y: image.height / 2) > 240, "existing opaque body")
}

@MainActor
private func testPreparesNormalizedTransparentBundleFrames() throws {
    for index in 1...4 {
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: "img/\(index).png"))
        let pngData = try FrameImageProcessor.makeNormalizedPNG(from: sourceData, pixelSize: 240)
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            runner.expectTrue(false, "normalized frame \(index) must decode")
            continue
        }
        runner.expectEqual(image.width, 240, "normalized frame \(index) width")
        runner.expectEqual(image.height, 240, "normalized frame \(index) height")
        runner.expectEqual(alphaValue(in: image, x: 0, y: 0), 0, "normalized frame \(index) corner")
    }
}

@MainActor
private func testReversibleFrameProcessingPreservesSourceUntilDisplayRemoval() throws {
    let opaqueInput = try Data(contentsOf: URL(fileURLWithPath: "img/2.png"))
    let source = try FrameImageProcessor.makeNormalizedSourcePNG(from: opaqueInput, pixelSize: 240)
    let preserved = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: source, removingLightBackground: false)
    let removed = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: source, removingLightBackground: true)

    runner.expectEqual(alphaValue(in: try decodePNG(preserved), x: 0, y: 0), 0, "aspect-fit margin preserved")
    runner.expectEqual(alphaValue(in: try decodePNG(removed), x: 0, y: 0), 0, "background removed")
    runner.expectEqual(alphaValue(in: try decodePNG(preserved), x: 10, y: 120), 255, "light source area remains opaque when removal is off")
    runner.expectEqual(alphaValue(in: try decodePNG(removed), x: 10, y: 120), 0, "connected light source area becomes transparent when removal is on")
}

@MainActor
private func testReversibleProcessingHandlesNonSquareJPEGAndAlphaPNG() throws {
    let jpeg = try makeOpaqueJPEGFixture()
    let normalizedJPEG = try FrameImageProcessor.makeNormalizedSourcePNG(from: jpeg, pixelSize: 240)
    let normalizedImage = try decodePNG(normalizedJPEG)
    runner.expectEqual(normalizedImage.width, 240, "JPEG normalized width")
    runner.expectEqual(normalizedImage.height, 240, "JPEG normalized height")
    runner.expectEqual(alphaValue(in: normalizedImage, x: 0, y: 0), 0, "JPEG aspect-fit margin transparent")
    runner.expectEqual(alphaValue(in: normalizedImage, x: 120, y: 120), 255, "JPEG source area opaque")

    let preservedJPEG = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: normalizedJPEG, removingLightBackground: false)
    let preservedImage = try decodePNG(preservedJPEG)
    runner.expectEqual(alphaValue(in: preservedImage, x: 0, y: 0), 0, "display false preserves JPEG margin")
    runner.expectEqual(pixelValue(in: preservedImage, x: 120, y: 120), pixelValue(in: normalizedImage, x: 120, y: 120), "display false preserves JPEG pixel")
    let removedJPEG = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: normalizedJPEG, removingLightBackground: true)
    runner.expectEqual(alphaValue(in: try decodePNG(removedJPEG), x: 0, y: 0), 0, "display true removes connected light background")

    let alphaSource = try FrameImageProcessor.makeNormalizedSourcePNG(
        from: Data(contentsOf: URL(fileURLWithPath: "img/1.png")), pixelSize: 240
    )
    let alphaPreserved = try FrameImageProcessor.makeDisplayPNG(fromNormalizedSource: alphaSource, removingLightBackground: false)
    let alphaPreservedImage = try decodePNG(alphaPreserved)
    let alphaSourceImage = try decodePNG(alphaSource)
    runner.expectEqual(alphaValue(in: alphaPreservedImage, x: 0, y: 0), 0, "alpha PNG transparency preserved")
    runner.expectEqual(pixelValue(in: alphaPreservedImage, x: 120, y: 120), pixelValue(in: alphaSourceImage, x: 120, y: 120), "display false preserves alpha PNG pixel")
}

private func decodePNG(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw FrameImageError.invalidImage
    }
    return image
}

private func pixelValue(in image: CGImage, x: Int, y: Int) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixel,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: CGFloat(-x), y: CGFloat(-(image.height - y - 1)))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixel
}

private func makeOpaqueJPEGFixture() throws -> Data {
    var pixels = [UInt8](repeating: 255, count: 80 * 40 * 4)
    guard let context = CGContext(
        data: &pixels,
        width: 80,
        height: 40,
        bitsPerComponent: 8,
        bytesPerRow: 80 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FrameImageError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 20, y: 10, width: 40, height: 20))
    guard let image = context.makeImage() else {
        throw FrameImageError.invalidImage
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw FrameImageError.invalidImage
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw FrameImageError.invalidImage
    }
    return output as Data
}

private func makeOrientedJPEGFixture(orientation: Int) throws -> Data {
    let width = 80
    let height = 40
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FrameImageError.contextCreationFailed
    }
    context.setFillColor(CGColor(red: 0.05, green: 0.2, blue: 0.65, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.95, green: 0.05, blue: 0.05, alpha: 1))
    context.fill(CGRect(x: 0, y: 20, width: 20, height: 20))
    guard let image = context.makeImage() else {
        throw FrameImageError.invalidImage
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw FrameImageError.invalidImage
    }
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 1.0,
        kCGImagePropertyOrientation: orientation
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw FrameImageError.invalidImage
    }
    return output as Data
}

private func redMarkerCentroid(in image: CGImage) -> CGPoint? {
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    var xTotal = 0
    var yTotal = 0
    var count = 0
    for y in 0..<image.height {
        for x in 0..<image.width {
            let offset = y * bytesPerRow + x * 4
            if pixels[offset] > 180, pixels[offset + 1] < 80, pixels[offset + 2] < 80 {
                xTotal += x
                yTotal += y
                count += 1
            }
        }
    }
    guard count > 0 else { return nil }
    return CGPoint(x: xTotal / count, y: yTotal / count)
}

@MainActor
private func testAppliesJPEGEXIFOrientationBeforeAspectFit() throws {
    let orientation6 = try decodePNG(
        FrameImageProcessor.makeNormalizedSourcePNG(
            from: makeOrientedJPEGFixture(orientation: 6),
            pixelSize: 240
        )
    )
    let orientation8 = try decodePNG(
        FrameImageProcessor.makeNormalizedSourcePNG(
            from: makeOrientedJPEGFixture(orientation: 8),
            pixelSize: 240
        )
    )

    for (image, label) in [(orientation6, "orientation 6"), (orientation8, "orientation 8")] {
        runner.expectEqual(alphaValue(in: image, x: 20, y: 120), 0, "\(label) creates horizontal margin after vertical rotation")
        runner.expectEqual(alphaValue(in: image, x: 120, y: 20), 255, "\(label) fills vertical extent after rotation")
    }

    let marker6 = redMarkerCentroid(in: orientation6)
    let marker8 = redMarkerCentroid(in: orientation8)
    runner.expectTrue(
        marker6.map { $0.x > 120 && $0.y < 120 } == true,
        "orientation 6 rotates upper-left marker to upper-right (actual: \(String(describing: marker6)))"
    )
    runner.expectTrue(
        marker8.map { $0.x < 120 && $0.y > 120 } == true,
        "orientation 8 rotates upper-left marker to lower-left (actual: \(String(describing: marker8)))"
    )
}

@MainActor
private func testPositionsPanelAtBottomRightAndClampsOffscreenOrigin() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let panelSize = CGSize(width: 120, height: 120)
    let expectedDefault = CGPoint(x: 1300, y: 20)

    runner.expectEqual(
        PanelPositioning.origin(saved: nil, panelSize: panelSize, visibleScreens: [screen]),
        expectedDefault,
        "default bottom-right origin"
    )
    runner.expectEqual(
        PanelPositioning.origin(saved: CGPoint(x: 5000, y: 5000), panelSize: panelSize, visibleScreens: [screen]),
        expectedDefault,
        "offscreen origin fallback"
    )
    runner.expectEqual(
        PanelPositioning.origin(saved: CGPoint(x: 100, y: 200), panelSize: panelSize, visibleScreens: [screen]),
        CGPoint(x: 100, y: 200),
        "valid saved origin"
    )
}

@MainActor
private func testMapsUsageStatesToWidgetPresentation() {
    let snapshot = UsageSnapshot(remainingPercent: 72, resetsAt: nil, fetchedAt: Date(timeIntervalSince1970: 10))
    runner.expectEqual(WidgetPresentation(state: .loading).text, "...", "loading text")
    runner.expectEqual(WidgetPresentation(state: .unauthenticated).text, "--%", "unauthenticated text")
    runner.expectEqual(WidgetPresentation(state: .failed("broken")).text, "ERR", "error text")
    runner.expectEqual(WidgetPresentation(state: .available(snapshot, isStale: false)).text, "72%", "available text")
    runner.expectEqual(WidgetPresentation(state: .available(snapshot, isStale: true)).showsWarning, true, "stale warning")
}

@MainActor
private func testScreenshotCharacterIsUprightIfRequested() throws {
    guard let path = ProcessInfo.processInfo.environment["TOKENPET_SCREENSHOT"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        runner.expectTrue(false, "screenshot must decode")
        return
    }
    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    var pinkRows: [Int] = []
    var greenRows: [Int] = []
    var greenColumns: [Int] = []
    for y in 0..<image.height {
        for x in (image.width / 2)..<image.width {
            let offset = y * bytesPerRow + x * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if red > 180, green < 170, blue < 190, red - green > 50 {
                pinkRows.append(y)
            }
            if green > 160, red < 170, blue < 220, green - red > 40 {
                greenRows.append(y)
                greenColumns.append(x)
            }
        }
    }

    runner.expectTrue(!pinkRows.isEmpty && !greenRows.isEmpty, "screenshot must contain character colors")
    if !pinkRows.isEmpty, !greenRows.isEmpty {
        let pinkAverage = pinkRows.reduce(0, +) / pinkRows.count
        let greenAverage = greenRows.reduce(0, +) / greenRows.count
        runner.expectTrue(pinkAverage < greenAverage, "character face must be above battery frame")

        let minGreenX = greenColumns.min()!
        let maxGreenX = greenColumns.max()!
        let minGreenY = greenRows.min()!
        let maxGreenY = greenRows.max()!
        let greenHeight = maxGreenY - minGreenY
        let textSearchMinY = minGreenY + greenHeight / 4
        let textSearchMaxY = maxGreenY - greenHeight / 4
        var whiteTextRows: [Int] = []
        for y in textSearchMinY...textSearchMaxY {
            for x in (minGreenX + 4)..<(maxGreenX - 4) {
                let offset = y * bytesPerRow + x * 4
                if pixels[offset] > 245, pixels[offset + 1] > 245, pixels[offset + 2] > 245 {
                    whiteTextRows.append(y)
                }
            }
        }
        runner.expectTrue(!whiteTextRows.isEmpty, "battery area must contain percent text")
        if !whiteTextRows.isEmpty {
            let whiteAverage = whiteTextRows.reduce(0, +) / whiteTextRows.count
            runner.expectTrue(
                abs(whiteAverage - greenAverage) <= 12,
                "percent text must be centered in battery area (text: \(whiteAverage), battery: \(greenAverage))"
            )
        }
    }
}

do {
    try testDecodesFiveHourUsageAndCalculatesRemainingPercent()
    testClampsRemainingPercent()
    try testBuildsAuthenticatedUsageRequest()
    try testParsesUsageAndRecognizesHTTPFailures()
    testKeepsLastValueWhenRefreshFails()
    try testDecodesClaudeCodeCredentialEnvelope()
    try testLoadsLegacyCredentialThroughAuthorizedSecurityToolFallback()
    testSecurityToolFallbackRequiresExplicitConsentAndNeverRunsAfterCancel()
    testDefinesPingPongAnimationSequence()
    try testCharacterProfileAndPercentLayoutContracts()
    try testKeepsPercentPositionsWithTheirCharacterFrames()
    testBuildsSafeCharacterMenuPresentation()
    try testPreservesCharacterSelectionAcrossTransientCatalogFailure()
    testDefinesCharacterMenuSiblingStructureAndRepresentedIDs()
    testShowsCharacterRefreshErrorsInCurrentMenuOpening()
    testReconcilesRuntimeDisplayWithoutLosingPersistedSelection()
    testEditorRefreshRecoversPersistedSelectionAfterCatalogFailure()
    testEditorDiscardTransitionsPreserveDirtyDraftUntilReplacementLoads()
    try testRemovesConnectedCheckerboardBackgroundFromOpaqueFrames()
    try testPreservesExistingTransparency()
    try testPreparesNormalizedTransparentBundleFrames()
    try testReversibleFrameProcessingPreservesSourceUntilDisplayRemoval()
    try testReversibleProcessingHandlesNonSquareJPEGAndAlphaPNG()
    try testAppliesJPEGEXIFOrientationBeforeAspectFit()
    testPositionsPanelAtBottomRightAndClampsOffscreenOrigin()
    testMapsUsageStatesToWidgetPresentation()
    try testScreenshotCharacterIsUprightIfRequested()
} catch {
    runner.failures += 1
    print("FAIL: unexpected top-level error — \(error)")
}

if runner.failures > 0 {
    print("\(runner.failures) test(s) failed")
    exit(1)
}

print("All TokenPetCore tests passed")
