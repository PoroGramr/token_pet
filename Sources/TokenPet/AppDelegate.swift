import AppKit
import TokenPetCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loginItemManager = LoginItemManager()
    private let languageSettings = LanguageSettings()
    private let builtInCharacterSettings = BuiltInCharacterSettings()
    private let refreshInterval = RefreshInterval.load()
    private lazy var usageController = UsageController(
        service: AnthropicUsageService(
            credentials: ClaudeKeychainStore(),
            transport: URLSessionUsageTransport()
        ),
        refreshInterval: refreshInterval.timeInterval
    )
    private lazy var characterStore = CharacterStore(
        rootURL: Self.characterStorageRoot,
        defaults: .standard
    )
    private lazy var characterRepository = CharacterRepository(
        store: characterStore,
        builtInSettings: builtInCharacterSettings
    )
    private var panelController: PetPanelController?
    private var characterEditorController: CharacterEditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = PetPanelController(
            loginItemManager: loginItemManager,
            characterRepository: characterRepository,
            languageSettings: languageSettings
        )
        self.panelController = panelController
        let characterEditorController = CharacterEditorWindowController(
            store: characterStore,
            repository: characterRepository,
            languageSettings: languageSettings,
            builtInSettings: builtInCharacterSettings
        ) { [weak panelController] character in
            panelController?.apply(character: character)
        }
        self.characterEditorController = characterEditorController
        panelController.onRefresh = { [weak self] in self?.usageController.refresh(manual: true) }
        panelController.onRefreshIntervalChanged = { [weak self] interval in
            self?.usageController.setRefreshInterval(interval.timeInterval)
        }
        panelController.onLogin = { [weak self] in self?.startClaudeLogin() }
        panelController.onCredentialFallbackChanged = { [weak self] in self?.usageController.refresh(manual: false) }
        panelController.onManageCharacters = { [weak characterEditorController] in
            characterEditorController?.show()
        }
        panelController.onLanguageChanged = { [weak characterEditorController] in
            characterEditorController?.updateLanguage()
        }
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
            panelController?.presentMenuError(languageSettings.text("Terminal에서 Claude 로그인을 시작하지 못했습니다"))
        }
    }

    private static var characterStorageRoot: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appendingPathComponent("TokenPet", isDirectory: true)
            .appendingPathComponent("Characters", isDirectory: true)
    }
}
