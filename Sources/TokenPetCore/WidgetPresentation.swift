public struct WidgetPresentation: Equatable, Sendable {
    public let text: String
    public let showsWarning: Bool
    public let statusMessage: String

    public init(state: UsageDisplayState) {
        switch state {
        case .loading:
            text = "..."
            showsWarning = false
            statusMessage = "사용량을 불러오는 중입니다"
        case .available(let snapshot, let isStale):
            text = "\(snapshot.remainingPercent)%"
            showsWarning = isStale
            statusMessage = isStale ? "마지막 정상 수치입니다" : "최근 사용량입니다"
        case .unauthenticated:
            text = "--%"
            showsWarning = false
            statusMessage = "Claude Code 로그인이 필요합니다"
        case .failed(let message):
            text = "ERR"
            showsWarning = true
            statusMessage = message
        }
    }
}
