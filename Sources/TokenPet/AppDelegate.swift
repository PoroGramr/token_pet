import AppKit
import TokenPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loginItemManager = LoginItemManager()
    private lazy var usageController = UsageController(
        service: AnthropicUsageService(
            credentials: ClaudeKeychainStore(),
            transport: URLSessionUsageTransport()
        )
    )
    private var panelController: PetPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = PetPanelController(loginItemManager: loginItemManager)
        self.panelController = panelController
        panelController.onRefresh = { [weak self] in self?.usageController.refresh(manual: true) }
        panelController.onLogin = { [weak self] in self?.startClaudeLogin() }
        panelController.onCredentialFallbackChanged = { [weak self] in self?.usageController.refresh(manual: false) }
        panelController.show()

        usageController.onStateChange = { [weak panelController] state in
            panelController?.update(state: state)
            if state == .failed("Keychain 접근이 거부되었습니다") {
                panelController?.offerCredentialFallbackIfNeeded()
            }
        }
        panelController.update(state: usageController.state)
        usageController.start()
        if let errorMessage = loginItemManager.enableOnFirstLaunch() {
            panelController.presentMenuError(errorMessage)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageController.stop()
    }

    private func startClaudeLogin() {
        do {
            try ClaudeLoginLauncher.openLoginCommand()
            usageController.beginLoginMonitoring()
        } catch {
            panelController?.presentMenuError("Terminal에서 Claude 로그인을 시작하지 못했습니다")
        }
    }
}
