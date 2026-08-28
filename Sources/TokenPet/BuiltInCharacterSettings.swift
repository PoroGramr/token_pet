import Foundation
import TokenPetCore

@MainActor
final class BuiltInCharacterSettings: ObservableObject {
    private struct Appearance: Codable {
        var positions: [NormalizedPoint]
        var fontSize: Double
    }

    private static let defaultsKey = "builtInCharacterAppearance"
    private static let legacyDefaultsKey = "builtInCharacterPercentPositions"
    private let defaults: UserDefaults
    @Published private var overrides: [String: Appearance]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.defaultsKey)
            ?? defaults.data(forKey: Self.legacyDefaultsKey)
            ?? Data()
        if let decoded = try? JSONDecoder().decode([String: Appearance].self, from: data) {
            overrides = decoded
        } else if let legacy = try? JSONDecoder().decode([String: [NormalizedPoint]].self, from: data) {
            overrides = legacy.mapValues { Appearance(positions: $0, fontSize: 22) }
        } else {
            overrides = [:]
        }
    }

    func positions(for profile: CharacterProfile) -> [NormalizedPoint] {
        guard let saved = overrides[profile.id.uuidString], saved.positions.count == profile.frameCount else {
            return profile.resolvedFramePercentPositions
        }
        return saved.positions.map(PercentLayout.clampedPosition)
    }

    func fontSize(for profile: CharacterProfile) -> Double {
        guard let saved = overrides[profile.id.uuidString] else { return profile.percentFontSize }
        return min(36, max(10, saved.fontSize))
    }

    func setPosition(_ position: NormalizedPoint, for profile: CharacterProfile, at index: Int) {
        var appearance = resolvedAppearance(for: profile)
        guard appearance.positions.indices.contains(index) else { return }
        appearance.positions[index] = PercentLayout.clampedPosition(position)
        save(appearance, for: profile)
    }

    func setFontSize(_ fontSize: Double, for profile: CharacterProfile) {
        var appearance = resolvedAppearance(for: profile)
        appearance.fontSize = min(36, max(10, fontSize))
        save(appearance, for: profile)
    }

    private func resolvedAppearance(for profile: CharacterProfile) -> Appearance {
        Appearance(positions: positions(for: profile), fontSize: fontSize(for: profile))
    }

    private func save(_ appearance: Appearance, for profile: CharacterProfile) {
        overrides[profile.id.uuidString] = appearance
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
