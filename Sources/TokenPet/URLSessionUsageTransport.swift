import Foundation
import TokenPetCore

struct URLSessionUsageTransport: UsageTransport, Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> UsageHTTPResult {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UsageClientError.network
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            result[String(describing: item.key).lowercased()] = String(describing: item.value)
        }
        return UsageHTTPResult(data: data, statusCode: response.statusCode, headers: headers)
    }
}
