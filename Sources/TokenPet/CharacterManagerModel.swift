import AppKit
import Combine
import TokenPetCore
import UniformTypeIdentifiers

@MainActor
final class CharacterManagerModel: ObservableObject {
    @Published private(set) var profiles: [CharacterProfile] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var draft: CharacterDraft?
    @Published private(set) var selectedFrameIndex = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDirty = false

    private let store: CharacterStore
    private let repository: CharacterRepository
    private let languageSettings: LanguageSettings
    private let onApply: (RuntimeCharacter) -> Void
    var confirmDiscard: (() -> Bool)?

    init(
        store: CharacterStore,
        repository: CharacterRepository,
        languageSettings: LanguageSettings,
        onApply: @escaping (RuntimeCharacter) -> Void
    ) {
        self.store = store
        self.repository = repository
        self.languageSettings = languageSettings
        self.onApply = onApply
        reloadProfiles()
    }

    var isBuiltInSelected: Bool { selectedID == CharacterRepository.builtInID }
    var editorState: CharacterEditorDraftState {
        CharacterEditorDraftState(selectedID: selectedID, draftID: draft?.id, isDirty: isDirty)
    }
    var canDeleteSelected: Bool {
        guard let selectedID, selectedID != CharacterRepository.builtInID else { return false }
        return profiles.contains { $0.id == selectedID }
    }
    var selectedFramePosition: NormalizedPoint? {
        guard let draft, draft.framePercentPositions.indices.contains(selectedFrameIndex) else { return nil }
        return draft.framePercentPositions[selectedFrameIndex]
    }

    func refresh() {
        guard !isDirty else { return }
        reloadProfiles()
    }

    func createCharacter() {
        guard confirmDiscardIfNeeded() else { return }
        let newDraft = CharacterDraft.new()
        let nextState = CharacterEditorStateTransitions.afterCreatingDraft(
            current: editorState,
            newDraftID: newDraft.id
        )
        selectedID = nextState.selectedID
        draft = newDraft
        selectedFrameIndex = 0
        errorMessage = nil
        isDirty = nextState.isDirty
    }

    func selectProfile(id: UUID) {
        guard selectedID != id, confirmDiscardIfNeeded() else { return }
        loadSelection(id: id)
    }

    func importFrames() {
        let panel = NSOpenPanel()
        panel.title = languageSettings.text("캐릭터 프레임 선택")
        panel.prompt = languageSettings.text("가져오기")
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        guard (3...4).contains(panel.urls.count) else {
            errorMessage = languageSettings.text("이미지는 한 번에 3장 또는 4장을 선택해 주세요.")
            return
        }

        do {
            let inputData = try panel.urls.map { try Data(contentsOf: $0) }
            let sources = try inputData.map {
                try FrameImageProcessor.makeNormalizedSourcePNG(from: $0, pixelSize: 240)
            }
            let removesBackground = draft?.removesLightBackground ?? false
            let displays = try sources.map {
                try FrameImageProcessor.makeDisplayPNG(
                    fromNormalizedSource: $0,
                    removingLightBackground: removesBackground
                )
            }
            var candidate = draft ?? CharacterDraft.new()
            candidate.sourceFrames = sources
            candidate.displayFrames = displays
            candidate.framePercentPositions = Array(
                repeating: candidate.percentPosition,
                count: sources.count
            )
            draft = candidate
            selectedFrameIndex = 0
            selectedID = candidate.id
            errorMessage = nil
            isDirty = true
        } catch {
            errorMessage = languageSettings.text("선택한 이미지를 읽거나 처리하지 못했습니다. PNG/JPG 파일을 확인해 주세요.")
        }
    }

    func moveFrame(from sourceIndex: Int, to destinationIndex: Int) {
        guard var candidate = draft else { return }
        let previousSelection = selectedFrameIndex
        candidate.moveFrame(from: sourceIndex, to: destinationIndex)
        draft = candidate
        selectedFrameIndex = movedSelection(
            previousSelection,
            movingFrom: sourceIndex,
            to: destinationIndex,
            frameCount: candidate.sourceFrames.count
        )
        errorMessage = nil
        isDirty = true
    }

    func updateName(_ name: String) {
        guard var candidate = draft else { return }
        candidate.name = name
        draft = candidate
        isDirty = true
    }

    func selectFrame(index: Int) {
        guard let draft, draft.displayFrames.indices.contains(index) else { return }
        selectedFrameIndex = index
    }

    func updateSelectedFramePercentPosition(_ position: NormalizedPoint) {
        guard var candidate = draft else { return }
        candidate.updateFramePercentPosition(position, at: selectedFrameIndex)
        draft = candidate
        isDirty = true
    }

    func updateFontSize(_ fontSize: Double) {
        guard var candidate = draft else { return }
        candidate.percentFontSize = min(36, max(10, fontSize))
        draft = candidate
        isDirty = true
    }

    func setRemovesLightBackground(_ removesLightBackground: Bool) {
        guard var candidate = draft, candidate.removesLightBackground != removesLightBackground else { return }
        do {
            let regenerated = try candidate.sourceFrames.map {
                try FrameImageProcessor.makeDisplayPNG(
                    fromNormalizedSource: $0,
                    removingLightBackground: removesLightBackground
                )
            }
            candidate.removesLightBackground = removesLightBackground
            candidate.displayFrames = regenerated
            draft = candidate
            errorMessage = nil
            isDirty = true
        } catch {
            errorMessage = languageSettings.text("배경 제거 설정을 적용하지 못했습니다. 기존 이미지는 유지됩니다.")
        }
    }

    func rebuildDisplayFrames() {
        guard var candidate = draft else { return }
        do {
            candidate.displayFrames = try candidate.sourceFrames.map {
                try FrameImageProcessor.makeDisplayPNG(
                    fromNormalizedSource: $0,
                    removingLightBackground: candidate.removesLightBackground
                )
            }
            draft = candidate
            errorMessage = nil
            isDirty = true
        } catch {
            errorMessage = languageSettings.text("이미지를 다시 처리하지 못했습니다. 기존 이미지는 유지됩니다.")
        }
    }

    func saveAndApply() {
        guard var candidate = draft else { return }
        let existingNames = profiles.filter { $0.id != candidate.id && $0.id != CharacterRepository.builtInID }.map(\.name)
        let validation = candidate.validation(existingNames: existingNames)
        guard validation.isValid else {
            errorMessage = validationMessage(for: validation.errors)
            return
        }

        candidate.name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let assets = CharacterAssets(
            profile: candidate.profile,
            sources: candidate.sourceFrames,
            frames: candidate.displayFrames
        )
        let preparedRuntime: RuntimeCharacter
        do {
            try CharacterRuntimeAssetValidator.validate(assets)
            let orderedFrames = try assets.profile.frameOrder.map { frameIndex -> NSImage in
                guard let image = NSImage(data: assets.frames[frameIndex]) else {
                    throw CharacterRuntimeAssetError.undecodableFrame(frameIndex)
                }
                return image
            }
            preparedRuntime = RuntimeCharacter(
                profile: assets.profile,
                frames: orderedFrames,
                framePercentPositions: FramePercentPositionMapper.ordered(
                    positions: assets.profile.resolvedFramePercentPositions,
                    frameOrder: assets.profile.frameOrder
                ),
                playbackIndices: FrameSequence.indices(frameCount: orderedFrames.count)
            )
        } catch {
            errorMessage = languageSettings.text("표시할 수 없는 이미지가 있어 저장하지 않았습니다. 기존 캐릭터는 그대로 유지됩니다.")
            return
        }

        do {
            try store.save(assets)
            store.selectedCharacterID = candidate.id
            onApply(preparedRuntime)
            draft = candidate
            selectedID = candidate.id
            isDirty = false
        } catch {
            errorMessage = languageSettings.text("캐릭터를 저장하지 못했습니다. 기존 캐릭터는 그대로 유지됩니다.")
            return
        }

        if !reloadProfiles() {
            errorMessage = languageSettings.text("캐릭터는 저장하고 적용했지만 목록을 새로 불러오지 못했습니다.")
        }
    }

    func deleteSelected() {
        guard let id = selectedID, id != CharacterRepository.builtInID else { return }
        do {
            let deletesAppliedCharacter = store.selectedCharacterID == id
            try store.delete(id: id)
            if deletesAppliedCharacter {
                onApply(try repository.select(id: nil))
            }
            profiles.removeAll { $0.id == id }
            selectedID = CharacterRepository.builtInID
            draft = nil
            selectedFrameIndex = 0
            errorMessage = nil
            isDirty = false
            reloadProfiles()
        } catch {
            errorMessage = languageSettings.text("캐릭터를 삭제하지 못했습니다.")
        }
    }

    @discardableResult
    func cancelChanges() -> Bool {
        reloadProfiles()
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        guard confirmDiscard?() ?? true else { return false }
        return true
    }

    @discardableResult
    private func reloadProfiles() -> Bool {
        let persistedSelectedID = store.selectedCharacterID
        do {
            profiles = try repository.availableCharacters()
        } catch {
            selectedID = CharacterEditorSelectionReconciliation.resolve(
                currentSelectedID: selectedID,
                persistedSelectedID: persistedSelectedID,
                builtInID: CharacterRepository.builtInID,
                catalog: .unavailable
            )
            errorMessage = languageSettings.text("캐릭터 목록을 불러오지 못했습니다. 기존 선택은 유지됩니다.")
            return false
        }

        let targetID = CharacterEditorSelectionReconciliation.resolve(
            currentSelectedID: selectedID,
            persistedSelectedID: persistedSelectedID,
            builtInID: CharacterRepository.builtInID,
            catalog: .available(Set(profiles.map(\.id)))
        ) ?? CharacterRepository.builtInID
        return loadSelection(id: targetID)
    }

    @discardableResult
    private func loadSelection(id: UUID) -> Bool {
        let currentState = editorState
        guard id != CharacterRepository.builtInID else {
            let nextState = CharacterEditorStateTransitions.afterSelectionAttempt(
                current: currentState,
                loadedSelection: .builtIn(id)
            )
            selectedID = nextState.selectedID
            draft = nil
            selectedFrameIndex = 0
            errorMessage = nil
            isDirty = nextState.isDirty
            return true
        }
        do {
            let loadedDraft = CharacterDraft(assets: try store.load(id: id))
            let nextState = CharacterEditorStateTransitions.afterSelectionAttempt(
                current: currentState,
                loadedSelection: .draft(id)
            )
            selectedID = nextState.selectedID
            draft = loadedDraft
            selectedFrameIndex = 0
            errorMessage = nil
            isDirty = nextState.isDirty
            return true
        } catch {
            let preservedState = CharacterEditorStateTransitions.afterSelectionAttempt(
                current: currentState,
                loadedSelection: nil
            )
            selectedID = preservedState.selectedID
            isDirty = preservedState.isDirty
            errorMessage = languageSettings.text("캐릭터 데이터를 불러오지 못했습니다. 기존 편집 상태를 유지합니다.")
            return false
        }
    }

    private func validationMessage(for errors: [String]) -> String {
        if errors.contains("name") { return languageSettings.text("캐릭터 이름은 1~40자로 입력해 주세요.") }
        if errors.contains("duplicateName") { return languageSettings.text("같은 이름의 캐릭터가 이미 있습니다.") }
        if errors.contains("frameCount") || errors.contains("displayFrames") || errors.contains("framePercentPositions") {
            return languageSettings.text("정상적인 이미지 3장 또는 4장이 필요합니다.")
        }
        if errors.contains("percentFontSize") { return languageSettings.text("글자 크기는 10~36pt로 설정해 주세요.") }
        return languageSettings.text("입력 내용을 확인해 주세요.")
    }

    private func movedSelection(
        _ selected: Int,
        movingFrom source: Int,
        to destination: Int,
        frameCount: Int
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        if selected == source { return min(destination, frameCount - 1) }
        if source < selected && selected <= destination { return selected - 1 }
        if destination <= selected && selected < source { return selected + 1 }
        return min(max(0, selected), frameCount - 1)
    }
}
