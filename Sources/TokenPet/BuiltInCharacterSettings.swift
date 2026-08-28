import Foundation
import TokenPetCore

@MainActor
final class BuiltInCharacterSettings: ObservableObject {
    private static let defaultsKey = "builtInCharacterPercentPositions"
    private let defaults: UserDefaults
    @Published private var overrides: [String: [NormalizedPoint]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.defaultsKey)
        overrides = (try? JSONDecoder().decode([String: [NormalizedPoint]].self, from: stored ?? Data())) ?? [:]
    }

    func positions(for profile: CharacterProfile) -> [NormalizedPoint] {
        guard let saved = overrides[profile.id.uuidString], saved.count == profile.frameCount else {
            return profile.resolvedFramePercentPositions
        }
        return saved.map(PercentLayout.clampedPosition)
    }

    func setPosition(_ position: NormalizedPoint, for profile: CharacterProfile, at index: Int) {
        var positions = positions(for: profile)
        guard positions.indices.contains(index) else { return }
        positions[index] = PercentLayout.clampedPosition(position)
        overrides[profile.id.uuidString] = positions
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
