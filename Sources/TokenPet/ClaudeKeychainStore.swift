import CryptoKit
import Foundation
import Security
import TokenPetCore

struct ClaudeKeychainStore: AccessTokenLoading, Sendable {
    func loadAccessToken() throws -> String {
        let userAllowedFallback = UserDefaults.standard.bool(forKey: CredentialFallbackPolicy.userDefaultsKey)
        if userAllowedFallback {
            return try SecurityToolCredentialStore(services: credentialServices).loadAccessToken()
        }

        do {
            let candidates = try credentialServices.enumerated().flatMap { priority, service in
                try loadCandidates(service: service, servicePriority: priority)
            }
            let valid = candidates.compactMap { candidate -> DecodedCandidate? in
                guard let credentials = try? ClaudeCredentialsCodec.decode(candidate.data) else { return nil }
                return DecodedCandidate(
                    accessToken: credentials.accessToken,
                    modifiedAt: candidate.modifiedAt,
                    servicePriority: candidate.servicePriority
                )
            }
            guard let selected = valid.sorted(by: DecodedCandidate.isPreferred).first else {
                throw UsageClientError.missingCredentials
            }
            return selected.accessToken
        } catch let error as UsageClientError {
            guard CredentialFallbackPolicy.shouldUseSecurityTool(for: error, userAllowed: userAllowedFallback) else {
                throw error
            }
            return try SecurityToolCredentialStore(services: credentialServices).loadAccessToken()
        }
    }

    private func loadCandidates(service: String, servicePriority: Int) throws -> [Candidate] {
        var result: CFTypeRef?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        case errSecInteractionNotAllowed:
            throw UsageClientError.keychainLocked
        case errSecAuthFailed:
            throw UsageClientError.keychainDenied
        case errSecUserCanceled:
            throw UsageClientError.keychainCanceled
        default:
            throw UsageClientError.keychain(statusCode: status)
        }

        let dictionaries: [[String: Any]]
        if let array = result as? [[String: Any]] {
            dictionaries = array
        } else if let dictionary = result as? [String: Any] {
            dictionaries = [dictionary]
        } else {
            return []
        }
        return dictionaries.compactMap { item in
            guard let data = item[kSecValueData as String] as? Data else { return nil }
            return Candidate(
                data: data,
                modifiedAt: item[kSecAttrModificationDate as String] as? Date ?? .distantPast,
                servicePriority: servicePriority
            )
        }
    }

    private var credentialServices: [String] {
        let legacy = "Claude Code-credentials"
        let configDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.path
        let digest = SHA256.hash(data: Data(configDirectory.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return ["\(legacy)-\(suffix)", legacy]
    }
}
private struct Candidate {
    let data: Data
    let modifiedAt: Date
    let servicePriority: Int
}

private struct DecodedCandidate {
    let accessToken: String
    let modifiedAt: Date
    let servicePriority: Int

    static func isPreferred(_ lhs: DecodedCandidate, _ rhs: DecodedCandidate) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.servicePriority < rhs.servicePriority
    }
}
