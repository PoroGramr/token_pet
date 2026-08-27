import AppKit
import SwiftUI
import TokenPetCore

@MainActor
final class CharacterEditorWindowController: NSObject, NSWindowDelegate {
    private let model: CharacterManagerModel
    private let languageSettings: LanguageSettings
    private let window: NSWindow

    init(
        store: CharacterStore,
        repository: CharacterRepository,
        languageSettings: LanguageSettings,
        onApply: @escaping (RuntimeCharacter) -> Void
    ) {
        let model = CharacterManagerModel(
            store: store,
            repository: repository,
            languageSettings: languageSettings,
            onApply: onApply
        )
        self.model = model
        self.languageSettings = languageSettings

        let hostingController = NSHostingController(rootView: CharacterManagerView(model: model, languageSettings: languageSettings))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = languageSettings.text("TokenPet 캐릭터 관리")
        window.contentViewController = hostingController
        window.minSize = NSSize(width: 900, height: 650)
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        super.init()

        window.delegate = self
        model.confirmDiscard = { [weak self] in
            self?.confirmDiscard() ?? false
        }
    }

    func show() {
        updateLanguage()
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func updateLanguage() {
        window.title = languageSettings.text("TokenPet 캐릭터 관리")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        guard confirmDiscard() else { return false }
        let currentState = model.editorState
        let didReload = model.cancelChanges()
        return CharacterEditorStateTransitions.afterCloseReload(
            current: currentState,
            reloaded: didReload ? model.editorState : nil
        ).shouldClose
    }

    private func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = languageSettings.text("저장하지 않은 변경을 버릴까요?")
        alert.informativeText = languageSettings.text("편집한 이미지와 설정은 저장되지 않습니다.")
        alert.addButton(withTitle: languageSettings.text("변경 버리기"))
        alert.addButton(withTitle: languageSettings.text("계속 편집"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
