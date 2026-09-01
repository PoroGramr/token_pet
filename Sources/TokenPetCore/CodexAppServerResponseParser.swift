import Foundation

public enum CodexAppServerResponseError: Error, Equatable, Sendable {
    case missingRateLimits
    case invalidRateLimits
    case server(String)
}

public enum CodexAppServerResponseParser {
    public static func parse(output: Data, requestID: Int, fetchedAt: Date) throws -> UsageSnapshot {
        guard let text = String(data: output, encoding: .utf8) else {
            throw CodexAppServerResponseError.invalidRateLimits
        }

        for line in text.split(whereSeparator: \Character.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == requestID else { continue }

            if let error = object["error"] as? [String: Any] {
                throw CodexAppServerResponseError.server(error["message"] as? String ?? "Codex App Server error")
            }
            guard let result = object["result"] as? [String: Any],
                  let rateLimits = result["rateLimits"] as? [String: Any],
                  let primary = rateLimits["primary"] as? [String: Any],
                  let usedPercent = (primary["usedPercent"] as? NSNumber)?.doubleValue,
                  usedPercent.isFinite, (0...100).contains(usedPercent) else {
                throw CodexAppServerResponseError.invalidRateLimits
            }

            let resetsAt = (primary["resetsAt"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue)
            }
            return UsageSnapshot(
                remainingPercent: Int((100 - usedPercent).rounded()),
                resetsAt: resetsAt,
                fetchedAt: fetchedAt
            )
        }
        throw CodexAppServerResponseError.missingRateLimits
    }
}

public enum CodexAppServerRequestFactory {
    public static func make(clientVersion: String, requestID: Int) -> Data {
        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "token_pet",
                        "title": "TokenPet",
                        "version": clientVersion
                    ]
                ]
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": requestID]
        ]
        let lines = messages.compactMap {
            try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
        }
        var output = Data()
        for line in lines {
            output.append(line)
            output.append(0x0A)
        }
        return output
    }
}
