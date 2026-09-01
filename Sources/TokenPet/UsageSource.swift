import Foundation

enum UsageSource: String, CaseIterable {
    case claude
    case codex

    private static let defaultsKey = "usageSource"

    static func load(defaults: UserDefaults = .standard) -> UsageSource {
        UsageSource(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .claude
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    var koreanTitle: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}
