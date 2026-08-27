import Darwin
import Foundation
import TokenPetCore

private final class Runner: @unchecked Sendable {
    private(set) var failures = 0

    func expect<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        if actual != expected {
            failures += 1
            print("FAIL: \(name) — expected \(expected), got \(actual)")
        }
    }

    func fail(_ name: String) {
        failures += 1
        print("FAIL: \(name)")
    }
}

private final class FakeCredentialLoader: AccessTokenLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func loadAccessToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !tokens.isEmpty else { throw UsageClientError.missingCredentials }
        if tokens.count == 1 { return tokens[0] }
        return tokens.removeFirst()
    }
}

private actor FakeTransport: UsageTransport {
    private var results: [UsageHTTPResult]
    private(set) var authorizationHeaders: [String] = []

    init(results: [UsageHTTPResult]) {
        self.results = results
    }

    func data(for request: URLRequest) async throws -> UsageHTTPResult {
        authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        return results.removeFirst()
    }
}

@main
private struct ServiceTestMain {
    static func main() async {
        let runner = Runner()
        let body = Data(#"{"five_hour":{"utilization":35,"resets_at":null}}"#.utf8)

        do {
            let credentials = FakeCredentialLoader(tokens: ["old-token", "new-token"])
            let transport = FakeTransport(results: [
                UsageHTTPResult(data: Data(), statusCode: 401, headers: [:]),
                UsageHTTPResult(data: body, statusCode: 200, headers: [:])
            ])
            let service = AnthropicUsageService(credentials: credentials, transport: transport)
            let snapshot = try await service.fetchUsage(now: Date(timeIntervalSince1970: 10))

            runner.expect(snapshot.remainingPercent, 65, "retry with externally refreshed credential")
            runner.expect(await transport.authorizationHeaders, ["Bearer old-token", "Bearer new-token"], "retry token order")
        } catch {
            runner.fail("externally refreshed credential should recover: \(error)")
        }

        do {
            let credentials = FakeCredentialLoader(tokens: ["same-token", "same-token"])
            let transport = FakeTransport(results: [UsageHTTPResult(data: Data(), statusCode: 401, headers: [:])])
            let service = AnthropicUsageService(credentials: credentials, transport: transport)
            _ = try await service.fetchUsage()
            runner.fail("unchanged rejected credential must stay unauthorized")
        } catch let error as UsageClientError {
            runner.expect(error, .unauthorized, "unchanged credential error")
        } catch {
            runner.fail("unexpected unchanged credential error: \(error)")
        }

        do {
            let credentials = FakeCredentialLoader(tokens: ["token"])
            let transport = FakeTransport(results: [
                UsageHTTPResult(data: Data(), statusCode: 429, headers: ["retry-after": "120"])
            ])
            let service = AnthropicUsageService(credentials: credentials, transport: transport)
            _ = try await service.fetchUsage()
            runner.fail("429 must fail")
        } catch let error as UsageClientError {
            runner.expect(error, .rateLimited(retryAfter: 120), "Retry-After mapping")
        } catch {
            runner.fail("unexpected rate limit error: \(error)")
        }

        do {
            let credentials = FakeCredentialLoader(tokens: ["old-token", "new-token"])
            let transport = FakeTransport(results: [
                UsageHTTPResult(data: body, statusCode: 200, headers: [:]),
                UsageHTTPResult(data: Data(), statusCode: 429, headers: ["retry-after": "90"])
            ])
            let service = AnthropicUsageService(credentials: credentials, transport: transport)
            _ = try await service.fetchUsage()
            _ = try await service.fetchUsageIfCredentialsChanged()
            runner.fail("credential-change 429 must fail")
        } catch let error as UsageClientError {
            runner.expect(error, .rateLimited(retryAfter: 90), "credential-change Retry-After mapping")
        } catch {
            runner.fail("unexpected credential-change rate limit error: \(error)")
        }

        do {
            let now = Date(timeIntervalSince1970: 1_445_412_360) // Wed, 21 Oct 2015 07:26:00 GMT
            let credentials = FakeCredentialLoader(tokens: ["token"])
            let transport = FakeTransport(results: [
                UsageHTTPResult(
                    data: Data(),
                    statusCode: 429,
                    headers: ["retry-after": "Wed, 21 Oct 2015 07:28:00 GMT"]
                )
            ])
            let service = AnthropicUsageService(credentials: credentials, transport: transport)
            _ = try await service.fetchUsage(now: now)
            runner.fail("HTTP-date Retry-After must fail")
        } catch let error as UsageClientError {
            runner.expect(error, .rateLimited(retryAfter: 120), "HTTP-date Retry-After mapping")
        } catch {
            runner.fail("unexpected HTTP-date rate limit error: \(error)")
        }

        if runner.failures > 0 {
            print("\(runner.failures) service test(s) failed")
            exit(1)
        }
        print("All TokenPet service tests passed")
    }
}
