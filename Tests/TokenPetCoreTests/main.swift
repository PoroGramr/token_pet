import Darwin
import CoreGraphics
import Foundation
import ImageIO
import TokenPetCore

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
    runner.expectEqual(FrameSequence.indices, [1, 2, 3, 4, 5, 4, 3, 2], "animation frame order")
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
    runner.expectEqual(FrameSequence.indices(frameCount: 4), [0, 1, 2, 3, 2, 1], "4-frame ping-pong")
    runner.expectEqual(try JSONDecoder().decode(CharacterProfile.self, from: JSONEncoder().encode(threeFrame)), threeFrame, "profile round trip")
    runner.expectEqual(PercentLayout.clampedPosition(NormalizedPoint(x: 2, y: -1)), NormalizedPoint(x: 1, y: 0), "position clamp")
    runner.expectTrue(CharacterProfileValidator.validate(threeFrame, existingNames: []).isEmpty, "valid profile")

    var duplicate = threeFrame
    duplicate.name = " cat "
    runner.expectTrue(!CharacterProfileValidator.validate(duplicate, existingNames: ["CAT"]).isEmpty, "duplicate name rejected")
    var invalidFrames = threeFrame
    invalidFrames.frameCount = 5
    runner.expectTrue(!CharacterProfileValidator.validate(invalidFrames, existingNames: []).isEmpty, "five user frames rejected")

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
    for index in 1...5 {
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
    try testRemovesConnectedCheckerboardBackgroundFromOpaqueFrames()
    try testPreservesExistingTransparency()
    try testPreparesNormalizedTransparentBundleFrames()
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
