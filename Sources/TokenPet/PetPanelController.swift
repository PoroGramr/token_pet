import AppKit
import TokenPetCore

@MainActor
final class PetPanelController: NSObject, NSMenuDelegate {
    private static let panelSize = NSSize(width: 120, height: 120)
    private let loginItemManager: LoginItemManager
    private let characterRepository: CharacterRepository
    private let languageSettings: LanguageSettings
    private let panel: NSPanel
    private let petView: PetView
    private let menu = NSMenu()
    private let characterMenu = NSMenu()
    private var displayedCharacterID = CharacterRepository.builtInID
    private let statusItem = NSMenuItem(title: "사용량을 불러오는 중입니다", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let credentialFallbackItem = NSMenuItem(
        title: "Apple security fallback 허용",
        action: #selector(toggleCredentialFallback),
        keyEquivalent: ""
    )
    private var state: UsageDisplayState = .loading
    private var transientError: String?
    private var offeredCredentialFallback = false
    private var refreshInterval = RefreshInterval.load()

    var onRefresh: (() -> Void)?
    var onRefreshIntervalChanged: ((RefreshInterval) -> Void)?
    var onLogin: (() -> Void)?
    var onCredentialFallbackChanged: (() -> Void)?
    var onManageCharacters: (() -> Void)?
    var onLanguageChanged: (() -> Void)?

    init(
        loginItemManager: LoginItemManager,
        characterRepository: CharacterRepository,
        languageSettings: LanguageSettings
    ) {
        self.loginItemManager = loginItemManager
        self.characterRepository = characterRepository
        self.languageSettings = languageSettings
        petView = PetView(frame: NSRect(origin: .zero, size: Self.panelSize))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        apply(character: characterRepository.selectedCharacter())
        configurePanel()
        configureMenu()
        restorePosition()
        observeWindowChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(state: UsageDisplayState) {
        self.state = state
        petView.update(state: state)
    }

    func apply(character: RuntimeCharacter) {
        displayedCharacterID = character.profile.id
        petView.apply(character: character)
    }

    func presentMenuError(_ message: String) {
        transientError = message
    }

    func menuWillOpen(_ menu: NSMenu) {
        let pendingError = transientError
        transientError = nil
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        credentialFallbackItem.state = isCredentialFallbackAllowed ? .on : .off
        statusItem.title = languageSettings.text(CharacterMenuStatusPresentation.message(
            pendingError: pendingError,
            refreshNotice: rebuildCharacterMenu(),
            usageMessage: WidgetPresentation(state: state).statusMessage
        ))
    }

    private func configurePanel() {
        panel.contentView = petView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
    }

    private func configureMenu() {
        menu.removeAllItems()
        menu.delegate = self
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: languageSettings.text("새로고침"), action: #selector(refresh), keyEquivalent: "r").target = self
        let refreshIntervalItem = NSMenuItem(title: languageSettings.text("자동 새로고침 간격"), action: nil, keyEquivalent: "")
        let refreshIntervalMenu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(
                title: languageSettings.text(interval.koreanTitle),
                action: #selector(selectRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval.rawValue
            item.state = interval == refreshInterval ? .on : .off
            refreshIntervalMenu.addItem(item)
        }
        refreshIntervalItem.submenu = refreshIntervalMenu
        menu.addItem(refreshIntervalItem)
        menu.addItem(withTitle: languageSettings.text("우측 하단으로 이동"), action: #selector(resetPosition), keyEquivalent: "") .target = self
        for descriptor in CharacterMenuStructureDescriptor.standard.rootItems {
            switch descriptor.role {
            case .characterSubmenu:
                let characterItem = NSMenuItem(title: languageSettings.text(descriptor.title), action: nil, keyEquivalent: "")
                characterItem.submenu = characterMenu
                menu.addItem(characterItem)
            case .manageCharacters:
                menu.addItem(
                    withTitle: languageSettings.text(descriptor.title),
                    action: #selector(manageCharacters),
                    keyEquivalent: ""
                ).target = self
            }
        }
        let languageItem = NSMenuItem(title: languageSettings.text("언어"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.menuTitle, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == languageSettings.language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(withTitle: languageSettings.text("Claude Code 로그인"), action: #selector(login), keyEquivalent: "").target = self
        credentialFallbackItem.title = languageSettings.text("Apple security fallback 허용")
        credentialFallbackItem.target = self
        menu.addItem(credentialFallbackItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        loginItem.title = languageSettings.text("로그인 시 실행")
        menu.addItem(withTitle: languageSettings.text("종료"), action: #selector(quit), keyEquivalent: "q").target = self
        petView.contextMenu = menu
    }

    private func rebuildCharacterMenu() -> CharacterMenuRefreshNotice {
        let snapshot: CharacterMenuSnapshot
        do {
            snapshot = try characterRepository.characterMenuPresentation()
        } catch {
            return .listUnavailable
        }

        characterMenu.removeAllItems()
        for entry in CharacterMenuStructureDescriptor.standard.selectionItems(for: snapshot) {
            let title = CharacterRepository.builtInIDs.contains(UUID(uuidString: entry.representedID) ?? UUID())
                ? languageSettings.text(entry.title)
                : entry.title
            let item = NSMenuItem(title: title, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.representedID
            item.state = entry.isSelected ? .on : .off
            characterMenu.addItem(item)
        }

        let currentState = CharacterRuntimeSelectionState(
            displayedID: displayedCharacterID,
            persistedSelectedID: characterRepository.persistedSelectedCharacterID
        )
        let reconciliation = CharacterRuntimeReconciliation.afterSuccessfulCatalog(
            current: currentState,
            effectiveSelectedID: snapshot.selectedID,
            persistedSelectedID: characterRepository.persistedSelectedCharacterID
        )
        guard apply(reconciliation.decision) else {
            return .runtimeUnavailable
        }
        return snapshot.didFallbackToBuiltIn ? .fallbackToBuiltIn : .none
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        let saved: NSPoint? = defaults.object(forKey: "panelOriginX") == nil ? nil : NSPoint(
            x: defaults.double(forKey: "panelOriginX"),
            y: defaults.double(forKey: "panelOriginY")
        )
        let origin = PanelPositioning.origin(
            saved: saved,
            panelSize: Self.panelSize,
            visibleScreens: orderedVisibleFrames
        )
        panel.setFrameOrigin(origin)
    }

    private var orderedVisibleFrames: [NSRect] {
        NSScreen.screens.map(\.visibleFrame)
    }

    private func observeWindowChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func refresh() { onRefresh?() }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let interval = RefreshInterval(rawValue: rawValue),
              interval != refreshInterval else { return }
        refreshInterval = interval
        interval.save()
        configureMenu()
        onRefreshIntervalChanged?(interval)
    }
    @objc private func login() { onLogin?() }
    @objc private func manageCharacters() { onManageCharacters?() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue),
              language != languageSettings.language else { return }
        languageSettings.language = language
        configureMenu()
        onLanguageChanged?()
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else {
            transientError = languageSettings.text("캐릭터 선택 정보를 확인하지 못했습니다")
            return
        }
        do {
            apply(character: try characterRepository.select(id: id))
        } catch {
            let currentState = CharacterRuntimeSelectionState(
                displayedID: displayedCharacterID,
                persistedSelectedID: characterRepository.persistedSelectedCharacterID
            )
            let reconciliation = CharacterRuntimeReconciliation.afterSelectionAttemptFailed(current: currentState)
            _ = apply(reconciliation.decision)
            transientError = languageSettings.text("캐릭터를 불러오지 못했습니다. 기존 캐릭터를 계속 표시합니다")
        }
    }

    private func apply(_ decision: CharacterRuntimeApplyDecision) -> Bool {
        switch decision {
        case .keepCurrent:
            return true
        case .apply(let id):
            do {
                apply(character: try characterRepository.select(id: id))
                return true
            } catch {
                return false
            }
        }
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
        } catch {
            transientError = languageSettings.text("로그인 시 실행 설정을 변경하지 못했습니다")
        }
    }

    func offerCredentialFallbackIfNeeded() {
        guard !offeredCredentialFallback, !isCredentialFallbackAllowed else { return }
        offeredCredentialFallback = true
        requestCredentialFallbackConsent()
    }

    @objc private func toggleCredentialFallback() {
        if isCredentialFallbackAllowed {
            UserDefaults.standard.set(false, forKey: CredentialFallbackPolicy.userDefaultsKey)
            onCredentialFallbackChanged?()
        } else {
            requestCredentialFallbackConsent()
        }
    }

    private var isCredentialFallbackAllowed: Bool {
        UserDefaults.standard.bool(forKey: CredentialFallbackPolicy.userDefaultsKey)
    }

    private func requestCredentialFallbackConsent() {
        let alert = NSAlert()
        alert.messageText = languageSettings.text("Apple security fallback을 허용할까요?")
        alert.informativeText = languageSettings.text("TokenPet은 Apple의 /usr/bin/security를 사용해 Claude Code 인증 정보를 읽기만 합니다. 토큰은 저장하거나 로그에 남기지 않습니다.")
        alert.addButton(withTitle: languageSettings.text("허용"))
        alert.addButton(withTitle: languageSettings.text("취소"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: CredentialFallbackPolicy.userDefaultsKey)
        onCredentialFallbackChanged?()
    }

    @objc private func resetPosition() {
        let origin = PanelPositioning.origin(
            saved: nil,
            panelSize: Self.panelSize,
            visibleScreens: orderedVisibleFrames
        )
        panel.setFrameOrigin(origin)
        savePosition()
    }

    @objc private func panelMoved(_ notification: Notification) {
        savePosition()
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        restorePosition()
    }

    private func savePosition() {
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "panelOriginX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "panelOriginY")
    }
}
