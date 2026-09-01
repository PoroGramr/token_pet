import Foundation
import TokenPetCore

@MainActor
final class UsageController: NSObject {
    private enum FetchKind {
        case current
        case credentialsChanged
    }

    private let service: AnthropicUsageService
    private let codexService: any CodexUsageFetching
    private var claudeStateMachine = UsageStateMachine()
    private var codexStateMachine = UsageStateMachine()
    private var source: UsageSource = .claude
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval
    private var loginTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastRequestStartedAt: Date?
    private var nextAllowedRefreshAt: Date?
    private var loginAttempts = 0
    private var fetchGeneration = 0

    private(set) var state: UsageDisplayState = .loading {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UsageDisplayState) -> Void)?

    init(
        service: AnthropicUsageService,
        codexService: any CodexUsageFetching,
        refreshInterval: TimeInterval = RefreshInterval.fiveMinutes.timeInterval
    ) {
        self.service = service
        self.codexService = codexService
        self.refreshInterval = refreshInterval
        super.init()
    }

    func start(source: UsageSource) {
        self.source = source
        refresh(manual: false)
        if refreshTimer == nil {
            scheduleRefreshTimer()
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval > 0, refreshInterval != interval else { return }
        refreshInterval = interval
        guard refreshTimer != nil else { return }
        refreshTimer?.invalidate()
        scheduleRefreshTimer()
    }

    private func scheduleRefreshTimer() {
        let timer = Timer(timeInterval: refreshInterval, target: self, selector: #selector(periodicRefresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        loginTimer?.invalidate()
        refreshTask?.cancel()
        fetchGeneration += 1
        refreshTimer = nil
        loginTimer = nil
        refreshTask = nil
    }

    func setSource(_ source: UsageSource) {
        guard self.source != source else { return }
        refreshTask?.cancel()
        fetchGeneration += 1
        refreshTask = nil
        loginTimer?.invalidate()
        loginTimer = nil
        nextAllowedRefreshAt = nil
        self.source = source
        state = .loading
        refresh(manual: false)
    }

    func refresh(manual: Bool) {
        startFetch(.current, manual: manual)
    }

    private func startFetch(_ kind: FetchKind, manual: Bool) {
        guard refreshTask == nil else { return }
        if source == .claude, let nextAllowedRefreshAt, nextAllowedRefreshAt > Date() { return }
        if manual, let lastRequestStartedAt, Date().timeIntervalSince(lastRequestStartedAt) < 10 {
            return
        }
        lastRequestStartedAt = Date()
        fetchGeneration += 1
        let generation = fetchGeneration
        let requestedSource = source
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if fetchGeneration == generation {
                    refreshTask = nil
                }
            }
            do {
                let snapshot: UsageSnapshot?
                switch requestedSource {
                case .claude:
                    switch kind {
                    case .current:
                        snapshot = try await service.fetchUsage()
                    case .credentialsChanged:
                        snapshot = try await service.fetchUsageIfCredentialsChanged()
                    }
                case .codex:
                    switch kind {
                    case .current:
                        snapshot = try await codexService.fetchUsage(now: Date())
                    case .credentialsChanged:
                        return
                    }
                }
                guard !Task.isCancelled, fetchGeneration == generation, source == requestedSource,
                      let snapshot else { return }
                switch requestedSource {
                case .claude:
                    state = claudeStateMachine.receive(snapshot)
                    loginTimer?.invalidate()
                    loginTimer = nil
                case .codex:
                    state = codexStateMachine.receive(snapshot)
                }
            } catch let error as UsageClientError {
                guard !Task.isCancelled, fetchGeneration == generation, source == requestedSource else { return }
                handleClaude(error)
            } catch let error as CodexUsageFetchError {
                guard !Task.isCancelled, fetchGeneration == generation, source == requestedSource else { return }
                state = codexStateMachine.fail(message: error.statusMessage)
            } catch {
                guard !Task.isCancelled, fetchGeneration == generation, source == requestedSource else { return }
                if requestedSource == .claude {
                    handleClaude(.network)
                } else {
                    state = codexStateMachine.fail(message: "Codex 사용량을 불러오지 못했습니다")
                }
            }
        }
    }

    private func handleClaude(_ error: UsageClientError) {
        if case .rateLimited(let retryAfter) = error {
            nextAllowedRefreshAt = Date().addingTimeInterval(retryAfter ?? 300)
        }
        state = claudeStateMachine.fail(error)
    }

    func beginLoginMonitoring() {
        guard source == .claude else { return }
        loginTimer?.invalidate()
        loginAttempts = 0
        let timer = Timer(timeInterval: 10, target: self, selector: #selector(pollForLogin), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        loginTimer = timer
    }

    @objc private func periodicRefresh() {
        refresh(manual: false)
    }

    @objc private func pollForLogin() {
        loginAttempts += 1
        checkForCredentialChange()
        if loginAttempts >= 30 {
            loginTimer?.invalidate()
            loginTimer = nil
        }
    }

    private func checkForCredentialChange() {
        startFetch(.credentialsChanged, manual: false)
    }
}
