import Foundation

public enum UsageClientError: Error, Equatable, Sendable {
    case missingCredentials
    case keychainLocked
    case keychainDenied
    case keychainCanceled
    case keychain(statusCode: Int32)
    case keychainToolUnavailable
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case incompatibleResponse
    case server(statusCode: Int)
    case network
}

public struct UsageSnapshot: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let fetchedAt: Date

    public init(remainingPercent: Int, resetsAt: Date?, fetchedAt: Date) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.fetchedAt = fetchedAt
    }
}

public enum UsageDisplayState: Equatable, Sendable {
    case loading
    case available(UsageSnapshot, isStale: Bool)
    case unauthenticated
    case failed(String)
}

public struct UsageStateMachine: Sendable {
    private var lastSnapshot: UsageSnapshot?

    public init() {}

    public mutating func receive(_ snapshot: UsageSnapshot) -> UsageDisplayState {
        lastSnapshot = snapshot
        return .available(snapshot, isStale: false)
    }

    public mutating func fail(_ error: UsageClientError) -> UsageDisplayState {
        if let lastSnapshot {
            return .available(lastSnapshot, isStale: true)
        }

        switch error {
        case .missingCredentials, .unauthorized:
            return .unauthenticated
        case .keychainLocked:
            return .failed("Mac 로그인 키체인이 잠겨 있습니다")
        case .keychainDenied:
            return .failed("Keychain 접근이 거부되었습니다")
        case .keychainCanceled:
            return .failed("Keychain 접근이 취소되었습니다")
        case .keychain:
            return .failed("Keychain 오류가 발생했습니다")
        case .keychainToolUnavailable:
            return .failed("Keychain 자격 증명 도구가 응답하지 않습니다")
        case .incompatibleResponse:
            return .failed("API 응답 형식이 변경되었습니다")
        case .rateLimited:
            return .failed("사용량 조회가 잠시 제한되었습니다")
        case .server:
            return .failed("Anthropic 서버 오류가 발생했습니다")
        case .network:
            return .failed("네트워크에 연결할 수 없습니다")
        }
    }

    public mutating func fail(message: String) -> UsageDisplayState {
        if let lastSnapshot {
            return .available(lastSnapshot, isStale: true)
        }
        return .failed(message)
    }
}

public enum UsageRequestFactory {
    public static func make(accessToken: String) throws -> URLRequest {
        guard !accessToken.isEmpty else {
            throw UsageClientError.missingCredentials
        }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw UsageClientError.incompatibleResponse
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

public enum UsageResponseParser {
    public static func parse(data: Data, statusCode: Int, fetchedAt: Date) throws -> UsageSnapshot {
        switch statusCode {
        case 200:
            do {
                let response = try JSONDecoder.tokenPet.decode(UsageResponse.self, from: data)
                guard let window = response.fiveHour else {
                    throw UsageClientError.incompatibleResponse
                }
                return UsageSnapshot(
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt,
                    fetchedAt: fetchedAt
                )
            } catch let error as UsageClientError {
                throw error
            } catch {
                throw UsageClientError.incompatibleResponse
            }
        case 401:
            throw UsageClientError.unauthorized
        case 429:
            throw UsageClientError.rateLimited(retryAfter: nil)
        default:
            throw UsageClientError.server(statusCode: statusCode)
        }
    }
}
