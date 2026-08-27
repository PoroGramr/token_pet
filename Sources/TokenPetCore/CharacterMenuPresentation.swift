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

public protocol CharacterMenuCatalog: AnyObject, Sendable {
    var selectedCharacterID: UUID? { get set }
    func list() throws -> [CharacterProfile]
}

extension CharacterStore: CharacterMenuCatalog {}

public struct CharacterMenuResolver: Sendable {
    private let catalog: any CharacterMenuCatalog
    private let builtInProfile: CharacterProfile

    public init(catalog: any CharacterMenuCatalog, builtInProfile: CharacterProfile) {
        self.catalog = catalog
        self.builtInProfile = builtInProfile
    }

    public func presentation() throws -> CharacterMenuSnapshot {
        let userProfiles = try catalog.list()
        let snapshot = CharacterMenuPresentation.make(
            profiles: [builtInProfile] + userProfiles,
            builtInID: builtInProfile.id,
            selectedID: catalog.selectedCharacterID
        )
        if snapshot.didFallbackToBuiltIn {
            catalog.selectedCharacterID = nil
        }
        return snapshot
    }
}

public enum CharacterMenuRootRole: Equatable, Sendable {
    case characterSubmenu
    case manageCharacters
}

public struct CharacterMenuRootItemDescriptor: Equatable, Sendable {
    public let title: String
    public let role: CharacterMenuRootRole

    public init(title: String, role: CharacterMenuRootRole) {
        self.title = title
        self.role = role
    }
}

public struct CharacterMenuSelectionItemDescriptor: Equatable, Sendable {
    public let title: String
    public let representedID: String
    public let isSelected: Bool

    public init(title: String, representedID: String, isSelected: Bool) {
        self.title = title
        self.representedID = representedID
        self.isSelected = isSelected
    }
}

public struct CharacterMenuStructureDescriptor: Equatable, Sendable {
    public static let standard = CharacterMenuStructureDescriptor(
        rootItems: [
            .init(title: "캐릭터", role: .characterSubmenu),
            .init(title: "캐릭터 관리…", role: .manageCharacters)
        ]
    )

    public let rootItems: [CharacterMenuRootItemDescriptor]

    public init(rootItems: [CharacterMenuRootItemDescriptor]) {
        self.rootItems = rootItems
    }

    public func selectionItems(for snapshot: CharacterMenuSnapshot) -> [CharacterMenuSelectionItemDescriptor] {
        snapshot.entries.map {
            CharacterMenuSelectionItemDescriptor(
                title: $0.title,
                representedID: $0.id.uuidString,
                isSelected: $0.isSelected
            )
        }
    }
}

public enum CharacterMenuRefreshNotice: Equatable, Sendable {
    case none
    case listUnavailable
    case fallbackToBuiltIn
    case runtimeUnavailable
}

public enum CharacterMenuStatusPresentation {
    public static func message(
        pendingError: String?,
        refreshNotice: CharacterMenuRefreshNotice,
        usageMessage: String
    ) -> String {
        switch refreshNotice {
        case .listUnavailable:
            return "캐릭터 목록을 불러오지 못했습니다"
        case .fallbackToBuiltIn:
            return "선택한 캐릭터를 불러오지 못해 기본 캐릭터로 돌아갔습니다"
        case .runtimeUnavailable:
            return "선택한 캐릭터를 표시하지 못했습니다"
        case .none:
            return pendingError ?? usageMessage
        }
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
