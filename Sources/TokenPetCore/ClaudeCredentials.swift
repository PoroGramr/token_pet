import Foundation

public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAtMilliseconds: Int64?

    public init(accessToken: String, expiresAtMilliseconds: Int64?) {
        self.accessToken = accessToken
        self.expiresAtMilliseconds = expiresAtMilliseconds
    }
}

public enum ClaudeCredentialsCodec {
    public static func decode(_ data: Data) throws -> ClaudeCredentials {
        do {
            let envelope = try JSONDecoder().decode(CredentialEnvelope.self, from: data)
            return ClaudeCredentials(
                accessToken: envelope.claudeAiOauth.accessToken,
                expiresAtMilliseconds: envelope.claudeAiOauth.expiresAt
            )
        } catch {
            throw UsageClientError.missingCredentials
        }
    }
}

private struct CredentialEnvelope: Decodable {
    let claudeAiOauth: CredentialPayload
}

private struct CredentialPayload: Decodable {
    let accessToken: String
    let expiresAt: Int64?
}
