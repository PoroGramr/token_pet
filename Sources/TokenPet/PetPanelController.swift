import AppKit
import TokenPetCore

@MainActor
final class PetPanelController: NSObject, NSMenuDelegate {
    private static let panelSize = NSSize(width: 120, height: 120)
    private let loginItemManager: LoginItemManager
    private let characterRepository: CharacterRepository
    private let panel: NSPanel
    private let petView: PetView
    private let menu = NSMenu()
    private let characterMenu = NSMenu()
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

    var onRefresh: (() -> Void)?
    var onLogin: (() -> Void)?
    var onCredentialFallbackChanged: (() -> Void)?
    var onManageCharacters: (() -> Void)?

    init(loginItemManager: LoginItemManager, characterRepository: CharacterRepository) {
        self.loginItemManager = loginItemManager
        self.characterRepository = characterRepository
        petView = PetView(frame: NSRect(origin: .zero, size: Self.panelSize))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        petView.apply(character: characterRepository.selectedCharacter())
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
        petView.apply(character: character)
    }

    func presentMenuError(_ message: String) {
        transientError = message
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusItem.title = transientError ?? WidgetPresentation(state: state).statusMessage
        transientError = nil
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        credentialFallbackItem.state = isCredentialFallbackAllowed ? .on : .off
        rebuildCharacterMenu()
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
        menu.delegate = self
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "새로고침", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "우측 하단으로 이동", action: #selector(resetPosition), keyEquivalent: "") .target = self
        let characterItem = NSMenuItem(title: "캐릭터", action: nil, keyEquivalent: "")
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)
        menu.addItem(withTitle: "Claude Code 로그인", action: #selector(login), keyEquivalent: "").target = self
        credentialFallbackItem.target = self
        menu.addItem(credentialFallbackItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        petView.contextMenu = menu
    }

    private func rebuildCharacterMenu() {
        let snapshot = characterRepository.characterMenuSnapshot()
        if snapshot.didFallbackToBuiltIn {
            petView.apply(character: characterRepository.selectedCharacter())
            transientError = "선택한 캐릭터를 불러오지 못해 기본 캐릭터로 돌아갔습니다"
        }

        characterMenu.removeAllItems()
        for entry in snapshot.entries {
            let item = NSMenuItem(title: entry.title, action: #selector(selectCharacter(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id.uuidString
            item.state = entry.isSelected ? .on : .off
            characterMenu.addItem(item)
        }
        characterMenu.addItem(.separator())
        characterMenu.addItem(withTitle: "캐릭터 관리…", action: #selector(manageCharacters), keyEquivalent: "").target = self
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
    @objc private func login() { onLogin?() }
    @objc private func manageCharacters() { onManageCharacters?() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else {
            transientError = "캐릭터 선택 정보를 확인하지 못했습니다"
            return
        }
        do {
            petView.apply(character: try characterRepository.select(id: id))
        } catch {
            if let builtIn = try? characterRepository.select(id: nil) {
                petView.apply(character: builtIn)
            }
            transientError = "캐릭터를 불러오지 못해 기본 캐릭터로 돌아갔습니다"
        }
        rebuildCharacterMenu()
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemManager.setEnabled(!loginItemManager.isEnabled)
        } catch {
            transientError = "로그인 시 실행 설정을 변경하지 못했습니다"
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
        alert.messageText = "Apple security fallback을 허용할까요?"
        alert.informativeText = "TokenPet은 Apple의 /usr/bin/security를 사용해 Claude Code 인증 정보를 읽기만 합니다. 토큰은 저장하거나 로그에 남기지 않습니다."
        alert.addButton(withTitle: "허용")
        alert.addButton(withTitle: "취소")
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
