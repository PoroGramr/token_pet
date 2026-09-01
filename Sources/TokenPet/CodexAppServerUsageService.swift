import Foundation
import TokenPetCore
import Darwin

protocol CodexUsageFetching: Sendable {
    func fetchUsage(now: Date) async throws -> UsageSnapshot
}

enum CodexUsageFetchError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed
    case timedOut
    case serverUnavailable
    case invalidResponse

    var statusMessage: String {
        switch self {
        case .executableNotFound: return "Codex CLI를 찾을 수 없습니다"
        case .launchFailed, .serverUnavailable: return "Codex App Server를 실행하지 못했습니다"
        case .timedOut: return "Codex 사용량 조회 시간이 초과되었습니다"
        case .invalidResponse: return "Codex 사용량 응답을 확인하지 못했습니다"
        }
    }
}

actor CodexAppServerUsageService: CodexUsageFetching {
    private static let requestID = 6
    private let executableLocator: CodexExecutableLocator
    private let timeout: TimeInterval

    init(executableLocator: CodexExecutableLocator = CodexExecutableLocator(), timeout: TimeInterval = 15) {
        self.executableLocator = executableLocator
        self.timeout = timeout
    }

    func fetchUsage(now: Date = Date()) async throws -> UsageSnapshot {
        guard let executableURL = executableLocator.locate() else {
            throw CodexUsageFetchError.executableNotFound
        }

        let request = CodexAppServerRequestFactory.make(
            clientVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            requestID: Self.requestID
        )
        let requestTimeout = timeout
        let output = try await Task.detached(priority: .utility) {
            try Self.run(executableURL: executableURL, request: request, timeout: requestTimeout)
        }.value
        do {
            return try CodexAppServerResponseParser.parse(
                output: output,
                requestID: Self.requestID,
                fetchedAt: now
            )
        } catch {
            throw CodexUsageFetchError.invalidResponse
        }
    }

    private static func run(executableURL: URL, request: Data, timeout: TimeInterval) throws -> Data {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
        } catch {
            throw CodexUsageFetchError.launchFailed
        }
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: request)
        } catch {
            process.terminate()
            throw CodexUsageFetchError.serverUnavailable
        }

        var output = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var descriptor = pollfd(
            fd: outputPipe.fileHandleForReading.fileDescriptor,
            events: Int16(POLLIN),
            revents: 0
        )
        while Date() < deadline {
            let remainingMilliseconds = max(1, min(250, Int(deadline.timeIntervalSinceNow * 1_000)))
            let result = Darwin.poll(&descriptor, 1, Int32(remainingMilliseconds))
            if result > 0, descriptor.revents & Int16(POLLIN) != 0 {
                let data = outputPipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                output.append(data)
                if containsResponse(output, requestID: Self.requestID) {
                    try? inputPipe.fileHandleForWriting.close()
                    if terminated.wait(timeout: .now() + 2) != .success {
                        process.terminate()
                        _ = terminated.wait(timeout: .now() + 2)
                    }
                    return output
                }
            }
            if !process.isRunning { break }
        }
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        _ = terminated.wait(timeout: .now() + 2)
        throw process.terminationStatus == 0
            ? CodexUsageFetchError.timedOut
            : CodexUsageFetchError.serverUnavailable
    }

    private static func containsResponse(_ output: Data, requestID: Int) -> Bool {
        guard let text = String(data: output, encoding: .utf8) else { return false }
        return text.split(whereSeparator: \Character.isNewline).contains { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return (object["id"] as? NSNumber)?.intValue == requestID
        }
    }
}

struct CodexExecutableLocator: Sendable {
    private var fileManager: FileManager { .default }

    func locate() -> URL? {
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nvmCandidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private var candidatePaths: [String] {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/codex" }
        return pathCandidates + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            home + "/.volta/bin/codex",
            home + "/.local/bin/codex",
            home + "/Library/pnpm/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/Codex.app/Contents/Resources/codex"
        ]
    }

    private var nvmCandidates: [URL] {
        let versions = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let directories = (try? fileManager.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return directories
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/codex") }
    }
}
