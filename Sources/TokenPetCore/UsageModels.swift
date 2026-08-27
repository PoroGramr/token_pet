import Foundation

public struct UsageResponse: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?

    public init(fiveHour: UsageWindow?) {
        self.fiveHour = fiveHour
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        min(100, max(0, Int((100 - utilization).rounded())))
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

public extension JSONDecoder {
    static var tokenPet: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: rawValue) ?? ISO8601DateFormatter().date(from: rawValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(rawValue)"
            )
        }
        return decoder
    }
}
