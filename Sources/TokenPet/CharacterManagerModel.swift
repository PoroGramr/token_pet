import AppKit
import Combine
import TokenPetCore
import UniformTypeIdentifiers

@MainActor
final class CharacterManagerModel: ObservableObject {
    @Published private(set) var profiles: [CharacterProfile] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var draft: CharacterDraft?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isDirty = false

    private let store: CharacterStore
    private let repository: CharacterRepository
    private let onApply: (RuntimeCharacter) -> Void
    var confirmDiscard: (() -> Bool)?

    init(
        store: CharacterStore,
        repository: CharacterRepository,
        onApply: @escaping (RuntimeCharacter) -> Void
    ) {
        self.store = store
        self.repository = repository
        self.onApply = onApply
        reloadProfiles(selecting: repository.selectedCharacter().profile.id)
    }

    var isBuiltInSelected: Bool { selectedID == CharacterRepository.builtInID }
    var canDeleteSelected: Bool {
        guard let selectedID, selectedID != CharacterRepository.builtInID else { return false }
        return profiles.contains { $0.id == selectedID }
    }

    func refresh() {
        guard !isDirty else { return }
        reloadProfiles(selecting: selectedID ?? CharacterRepository.builtInID)
    }

    func createCharacter() {
        guard confirmDiscardIfNeeded() else { return }
        let newDraft = CharacterDraft.new()
        selectedID = newDraft.id
        draft = newDraft
        errorMessage = nil
        isDirty = true
    }

    func selectProfile(id: UUID) {
        guard selectedID != id, confirmDiscardIfNeeded() else { return }
        loadSelection(id: id)
    }

    func importFrames() {
        let panel = NSOpenPanel()
        panel.title = "캐릭터 프레임 선택"
        panel.prompt = "가져오기"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        guard (3...4).contains(panel.urls.count) else {
            errorMessage = "이미지는 한 번에 3장 또는 4장을 선택해 주세요."
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
            draft = candidate
            selectedID = candidate.id
            errorMessage = nil
            isDirty = true
        } catch {
            errorMessage = "선택한 이미지를 읽거나 처리하지 못했습니다. PNG/JPG 파일을 확인해 주세요."
        }
    }

    func moveFrame(from sourceIndex: Int, to destinationIndex: Int) {
        guard var candidate = draft else { return }
        candidate.moveFrame(from: sourceIndex, to: destinationIndex)
        draft = candidate
        errorMessage = nil
        isDirty = true
    }

    func updateName(_ name: String) {
        guard var candidate = draft else { return }
        candidate.name = name
        draft = candidate
        isDirty = true
    }

    func updatePercentPosition(_ position: NormalizedPoint) {
        guard var candidate = draft else { return }
        candidate.percentPosition = PercentLayout.clampedPosition(position)
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
            errorMessage = "배경 제거 설정을 적용하지 못했습니다. 기존 이미지는 유지됩니다."
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
            errorMessage = "이미지를 다시 처리하지 못했습니다. 기존 이미지는 유지됩니다."
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
        do {
            let assets = CharacterAssets(
                profile: candidate.profile,
                sources: candidate.sourceFrames,
                frames: candidate.displayFrames
            )
            try store.save(assets)
            let runtime = try repository.select(id: candidate.id)
            onApply(runtime)
            draft = candidate
            selectedID = candidate.id
            profiles = repository.availableCharacters()
            errorMessage = nil
            isDirty = false
        } catch {
            errorMessage = "캐릭터를 저장하지 못했습니다. 기존 캐릭터는 그대로 유지됩니다."
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
            reloadProfiles(selecting: CharacterRepository.builtInID)
            errorMessage = nil
            isDirty = false
        } catch {
            errorMessage = "캐릭터를 삭제하지 못했습니다."
        }
    }

    func cancelChanges() {
        let persistedID = profiles.contains { $0.id == selectedID }
            ? selectedID
            : CharacterRepository.builtInID
        loadSelection(id: persistedID ?? CharacterRepository.builtInID)
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        guard confirmDiscard?() ?? true else { return false }
        isDirty = false
        return true
    }

    private func reloadProfiles(selecting id: UUID) {
        profiles = repository.availableCharacters()
        let availableIDs = Set(profiles.map(\.id))
        loadSelection(id: availableIDs.contains(id) ? id : CharacterRepository.builtInID)
    }

    private func loadSelection(id: UUID) {
        selectedID = id
        errorMessage = nil
        isDirty = false
        guard id != CharacterRepository.builtInID else {
            draft = nil
            return
        }
        do {
            draft = CharacterDraft(assets: try store.load(id: id))
        } catch {
            selectedID = CharacterRepository.builtInID
            draft = nil
            errorMessage = "캐릭터 데이터를 불러오지 못해 기본 캐릭터를 표시합니다."
        }
    }

    private func validationMessage(for errors: [String]) -> String {
        if errors.contains("name") { return "캐릭터 이름은 1~40자로 입력해 주세요." }
        if errors.contains("duplicateName") { return "같은 이름의 캐릭터가 이미 있습니다." }
        if errors.contains("frameCount") || errors.contains("displayFrames") {
            return "정상적인 이미지 3장 또는 4장이 필요합니다."
        }
        if errors.contains("percentFontSize") { return "글자 크기는 10~36pt로 설정해 주세요." }
        return "입력 내용을 확인해 주세요."
    }
}
