import Foundation

public protocol AccessTokenLoading: Sendable {
    func loadAccessToken() throws -> String
}

public struct UsageHTTPResult: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol UsageTransport: Sendable {
    func data(for request: URLRequest) async throws -> UsageHTTPResult
}

public actor AnthropicUsageService {
    private let credentials: any AccessTokenLoading
    private let transport: any UsageTransport
    private var lastAttemptedAccessToken: String?

    public init(credentials: any AccessTokenLoading, transport: any UsageTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    public func fetchUsage(now: Date = Date()) async throws -> UsageSnapshot {
        let accessToken = try credentials.loadAccessToken()
        lastAttemptedAccessToken = accessToken
        do {
            return try await requestUsage(accessToken: accessToken, now: now)
        } catch UsageClientError.unauthorized {
            let latestAccessToken = try credentials.loadAccessToken()
            guard latestAccessToken != accessToken else {
                throw UsageClientError.unauthorized
            }
            lastAttemptedAccessToken = latestAccessToken
            return try await requestUsage(accessToken: latestAccessToken, now: now)
        }
    }

    public func fetchUsageIfCredentialsChanged(now: Date = Date()) async throws -> UsageSnapshot? {
        let accessToken = try credentials.loadAccessToken()
        guard accessToken != lastAttemptedAccessToken else { return nil }
        lastAttemptedAccessToken = accessToken
        return try await requestUsage(accessToken: accessToken, now: now)
    }

    private func requestUsage(accessToken: String, now: Date) async throws -> UsageSnapshot {
        do {
            let request = try UsageRequestFactory.make(accessToken: accessToken)
            let result = try await transport.data(for: request)
            if result.statusCode == 429 {
                let retryAfter = result.headers["retry-after"].flatMap {
                    RetryAfterParser.seconds(from: $0, relativeTo: now)
                }
                throw UsageClientError.rateLimited(retryAfter: retryAfter)
            }
            return try UsageResponseParser.parse(
                data: result.data,
                statusCode: result.statusCode,
                fetchedAt: now
            )
        } catch let error as UsageClientError {
            throw error
        } catch {
            throw UsageClientError.network
        }
    }
}

private enum RetryAfterParser {
    static func seconds(from value: String, relativeTo now: Date) -> TimeInterval? {
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
