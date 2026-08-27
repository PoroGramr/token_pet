import Foundation

public struct CharacterRuntimeSelectionState: Equatable, Sendable {
    public let displayedID: UUID
    public let persistedSelectedID: UUID?

    public init(displayedID: UUID, persistedSelectedID: UUID?) {
        self.displayedID = displayedID
        self.persistedSelectedID = persistedSelectedID
    }
}

public enum CharacterRuntimeApplyDecision: Equatable, Sendable {
    case keepCurrent
    case apply(UUID)
}

public struct CharacterRuntimeReconciliationResult: Equatable, Sendable {
    public let state: CharacterRuntimeSelectionState
    public let decision: CharacterRuntimeApplyDecision

    public init(state: CharacterRuntimeSelectionState, decision: CharacterRuntimeApplyDecision) {
        self.state = state
        self.decision = decision
    }
}

public enum CharacterRuntimeReconciliation {
    public static func afterSelectionAttemptFailed(
        current: CharacterRuntimeSelectionState
    ) -> CharacterRuntimeReconciliationResult {
        CharacterRuntimeReconciliationResult(state: current, decision: .keepCurrent)
    }

    public static func afterSuccessfulCatalog(
        current: CharacterRuntimeSelectionState,
        effectiveSelectedID: UUID,
        persistedSelectedID: UUID?
    ) -> CharacterRuntimeReconciliationResult {
        let state = CharacterRuntimeSelectionState(
            displayedID: current.displayedID,
            persistedSelectedID: persistedSelectedID
        )
        let decision: CharacterRuntimeApplyDecision = current.displayedID == effectiveSelectedID
            ? .keepCurrent
            : .apply(effectiveSelectedID)
        return CharacterRuntimeReconciliationResult(state: state, decision: decision)
    }
}

public enum CharacterEditorCatalogAvailability: Equatable, Sendable {
    case unavailable
    case available(Set<UUID>)
}

public enum CharacterEditorSelectionReconciliation {
    public static func resolve(
        currentSelectedID: UUID?,
        persistedSelectedID: UUID?,
        builtInID: UUID,
        catalog: CharacterEditorCatalogAvailability
    ) -> UUID? {
        switch catalog {
        case .unavailable:
            return currentSelectedID
        case .available(let availableIDs):
            let persistedOrBuiltIn = persistedSelectedID ?? builtInID
            return availableIDs.contains(persistedOrBuiltIn) ? persistedOrBuiltIn : builtInID
        }
    }
}
