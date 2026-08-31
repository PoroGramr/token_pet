import Foundation

enum RefreshInterval: Int, CaseIterable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1_800

    private static let defaultsKey = "usageRefreshInterval"

    var timeInterval: TimeInterval { TimeInterval(rawValue) }

    var koreanTitle: String {
        switch self {
        case .oneMinute: return "1분"
        case .fiveMinutes: return "5분"
        case .tenMinutes: return "10분"
        case .thirtyMinutes: return "30분"
        }
    }

    static func load(defaults: UserDefaults = .standard) -> RefreshInterval {
        RefreshInterval(rawValue: defaults.integer(forKey: defaultsKey)) ?? .fiveMinutes
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
