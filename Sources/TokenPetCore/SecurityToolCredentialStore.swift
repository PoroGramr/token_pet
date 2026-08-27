import Darwin
import Foundation

public enum CredentialFallbackPolicy {
    public static let userDefaultsKey = "allowsAppleSecurityToolCredentialFallback"

    public static func shouldUseSecurityTool(for error: UsageClientError, userAllowed: Bool) -> Bool {
        guard userAllowed else { return false }
        if case .keychainDenied = error { return true }
        return false
    }
}

public protocol CredentialDataReading: Sendable {
    func readCredentialData(service: String) throws -> Data?
}

public struct SecurityToolCredentialStore: AccessTokenLoading, Sendable {
    private let services: [String]
    private let reader: any CredentialDataReading

    public init(
        services: [String],
        reader: any CredentialDataReading = AppleSecurityToolCredentialReader()
    ) {
        self.services = services
        self.reader = reader
    }

    public func loadAccessToken() throws -> String {
        for service in services {
            guard let data = try reader.readCredentialData(service: service) else { continue }
            if let credentials = try? ClaudeCredentialsCodec.decode(data) {
                return credentials.accessToken
            }
        }
        throw UsageClientError.missingCredentials
    }
}

public struct AppleSecurityToolCredentialReader: CredentialDataReading, Sendable {
    private static let maximumOutputBytes = 64 * 1024
    private static let timeout: TimeInterval = 5

    public init() {}

    public func readCredentialData(service: String) throws -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            let buffer = LimitedCredentialBuffer(maximumBytes: Self.maximumOutputBytes)
            let outputHandle = output.fileHandleForReading
            outputHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                if !buffer.append(chunk), process.isRunning {
                    process.terminate()
                }
            }
            defer { outputHandle.readabilityHandler = nil }
            try process.run()
            let deadline = Date().addingTimeInterval(Self.timeout)
            while process.isRunning, Date() < deadline, !Task<Never, Never>.isCancelled {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw UsageClientError.keychainToolUnavailable
            }
            outputHandle.readabilityHandler = nil
            _ = buffer.append(outputHandle.readDataToEndOfFile())
            guard !buffer.exceededLimit else {
                throw UsageClientError.keychainToolUnavailable
            }
            switch process.terminationStatus {
            case 0:
                return buffer.data
            case 44:
                return nil
            default:
                throw UsageClientError.keychainDenied
            }
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.keychainDenied
        }
    }
}

private final class LimitedCredentialBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var storage = Data()
    private var didExceedLimit = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var data: Data {
        lock.withLock { storage }
    }

    var exceededLimit: Bool {
        lock.withLock { didExceedLimit }
    }

    func append(_ data: Data) -> Bool {
        lock.withLock {
            guard !didExceedLimit, storage.count + data.count <= maximumBytes else {
                didExceedLimit = true
                return false
            }
            storage.append(data)
            return true
        }
    }
}
