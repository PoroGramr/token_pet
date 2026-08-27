import Foundation
import TokenPetCore

@MainActor
final class UsageController: NSObject {
    private enum FetchKind {
        case current
        case credentialsChanged
    }

    private let service: AnthropicUsageService
    private var stateMachine = UsageStateMachine()
    private var refreshTimer: Timer?
    private var loginTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var lastRequestStartedAt: Date?
    private var nextAllowedRefreshAt: Date?
    private var loginAttempts = 0

    private(set) var state: UsageDisplayState = .loading {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((UsageDisplayState) -> Void)?

    init(service: AnthropicUsageService) {
        self.service = service
        super.init()
    }

    func start() {
        refresh(manual: false)
        let timer = Timer(timeInterval: 300, target: self, selector: #selector(periodicRefresh), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        loginTimer?.invalidate()
        refreshTask?.cancel()
    }

    func refresh(manual: Bool) {
        startFetch(.current, manual: manual)
    }

    private func startFetch(_ kind: FetchKind, manual: Bool) {
        guard refreshTask == nil else { return }
        if let nextAllowedRefreshAt, nextAllowedRefreshAt > Date() { return }
        if manual, let lastRequestStartedAt, Date().timeIntervalSince(lastRequestStartedAt) < 10 {
            return
        }
        lastRequestStartedAt = Date()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            do {
                let snapshot: UsageSnapshot?
                switch kind {
                case .current:
                    snapshot = try await service.fetchUsage()
                case .credentialsChanged:
                    snapshot = try await service.fetchUsageIfCredentialsChanged()
                }
                guard let snapshot else { return }
                state = stateMachine.receive(snapshot)
                loginTimer?.invalidate()
                loginTimer = nil
            } catch let error as UsageClientError {
                handle(error)
            } catch {
                handle(.network)
            }
        }
    }

    private func handle(_ error: UsageClientError) {
        if case .rateLimited(let retryAfter) = error {
            nextAllowedRefreshAt = Date().addingTimeInterval(retryAfter ?? 300)
        }
        state = stateMachine.fail(error)
    }

    func beginLoginMonitoring() {
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
