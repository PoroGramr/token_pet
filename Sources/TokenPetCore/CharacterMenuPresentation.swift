import Foundation

public struct CharacterMenuEntry: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let isSelected: Bool

    public init(id: UUID, title: String, isSelected: Bool) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}

public struct CharacterMenuSnapshot: Equatable, Sendable {
    public let entries: [CharacterMenuEntry]
    public let selectedID: UUID
    public let didFallbackToBuiltIn: Bool

    public init(entries: [CharacterMenuEntry], selectedID: UUID, didFallbackToBuiltIn: Bool) {
        self.entries = entries
        self.selectedID = selectedID
        self.didFallbackToBuiltIn = didFallbackToBuiltIn
    }
}

public enum CharacterMenuPresentation {
    public static func make(
        profiles: [CharacterProfile],
        builtInID: UUID,
        selectedID: UUID?
    ) -> CharacterMenuSnapshot {
        let orderedProfiles = profiles.filter { $0.id == builtInID }
            + profiles.filter { $0.id != builtInID }
        let availableIDs = Set(orderedProfiles.map(\.id))
        let resolvedSelectedID = selectedID.flatMap { availableIDs.contains($0) ? $0 : nil } ?? builtInID
        let entries = orderedProfiles.map {
            CharacterMenuEntry(id: $0.id, title: $0.name, isSelected: $0.id == resolvedSelectedID)
        }
        return CharacterMenuSnapshot(
            entries: entries,
            selectedID: resolvedSelectedID,
            didFallbackToBuiltIn: selectedID != nil && selectedID != builtInID && resolvedSelectedID == builtInID
        )
    }
}
