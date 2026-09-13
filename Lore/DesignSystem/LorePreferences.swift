import SwiftUI
import Observation

enum LoreTheme: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
enum LoreAccent: String, CaseIterable, Identifiable {
    case violet = "Violet", blue = "Blue", mint = "Mint", rose = "Rose"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .violet: Color(red: 0.49, green: 0.39, blue: 0.88)
        case .blue: Color(red: 0.25, green: 0.49, blue: 0.91)
        case .mint: Color(red: 0.16, green: 0.61, blue: 0.49)
        case .rose: Color(red: 0.78, green: 0.36, blue: 0.55)
        }
    }
}
enum PulseMode: String, Codable, CaseIterable, Identifiable {
    case standard = "Stay awake", closedLid = "Lid closed"
    var id: String { rawValue }
}
enum PulseDuration: Int, Codable, CaseIterable, Identifiable {
    case agents = 0, fifteen = 900, thirty = 1800, hour = 3600, twoHours = 7200, fourHours = 14400
    var id: Int { rawValue }
    var title: String { switch self { case .agents: "Until agents finish"; case .fifteen: "15 minutes"; case .thirty: "30 minutes"; case .hour: "1 hour"; case .twoHours: "2 hours"; case .fourHours: "4 hours" } }
}

struct PulsePreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var mode: PulseMode
    var duration: PulseDuration
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 40 && !(mode == .closedLid && duration == .agents) }
}

@MainActor @Observable final class LorePreferences {
    static let shared = LorePreferences()
    @ObservationIgnored private let defaults: UserDefaults
    var favoriteProjectIDs: [String] { didSet { defaults.set(favoriteProjectIDs, forKey: "projects.favorites") } }
    var pulsePresets: [PulsePreset] { didSet { if let data = try? JSONEncoder().encode(pulsePresets) { defaults.set(data, forKey: "pulse.presets.v1") } } }
    var theme: LoreTheme { didSet { defaults.set(theme.rawValue, forKey: "appearance.theme") } }
    var accent: LoreAccent { didSet { defaults.set(accent.rawValue, forKey: "appearance.accent") } }
    var compact: Bool { didSet { defaults.set(compact, forKey: "appearance.compact") } }
    var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "appearance.reduceMotion") } }
    var relaxedHover: Bool { didSet { defaults.set(relaxedHover, forKey: "notch.relaxedHover") } }
    var showPulseTime: Bool { didSet { defaults.set(showPulseTime, forKey: "pulse.showMenuTime") } }
    var pulseMode: PulseMode { didSet { defaults.set(pulseMode.rawValue, forKey: "pulse.defaultMode"); if pulseMode == .closedLid && pulseDuration == .agents { pulseDuration = .hour } } }
    var pulseDuration: PulseDuration { didSet { defaults.set(pulseDuration.rawValue, forKey: "pulse.defaultDuration") } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen: Set<String> = []
        favoriteProjectIDs = (defaults.stringArray(forKey: "projects.favorites") ?? []).filter { seen.insert($0).inserted }
        let presets = defaults.data(forKey: "pulse.presets.v1").flatMap { try? JSONDecoder().decode([PulsePreset].self, from: $0) } ?? []
        var presetIDs: Set<UUID> = []
        pulsePresets = presets.filter { $0.isValid && presetIDs.insert($0.id).inserted }
        theme = LoreTheme(rawValue: defaults.string(forKey: "appearance.theme") ?? "") ?? .system
        accent = LoreAccent(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .violet
        compact = defaults.bool(forKey: "appearance.compact")
        reduceMotion = defaults.bool(forKey: "appearance.reduceMotion")
        relaxedHover = defaults.bool(forKey: "notch.relaxedHover")
        showPulseTime = defaults.bool(forKey: "pulse.showMenuTime")
        pulseMode = PulseMode(rawValue: defaults.string(forKey: "pulse.defaultMode") ?? "") ?? .standard
        pulseDuration = defaults.object(forKey: "pulse.defaultDuration") == nil ? .hour : PulseDuration(rawValue: defaults.integer(forKey: "pulse.defaultDuration")) ?? .hour
        if pulseMode == .closedLid && pulseDuration == .agents { pulseDuration = .hour }
    }
    func toggleFavorite(_ id: String) {
        if favoriteProjectIDs.contains(id) { favoriteProjectIDs.removeAll { $0 == id } }
        else { favoriteProjectIDs.append(id) }
    }
    @discardableResult func savePreset(name: String) -> Bool {
        let value = PulsePreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines), mode: pulseMode, duration: pulseDuration)
        guard value.isValid else { return false }
        if let index = pulsePresets.firstIndex(where: { $0.name.caseInsensitiveCompare(value.name) == .orderedSame }) {
            var updated = value; updated.id = pulsePresets[index].id; pulsePresets[index] = updated
        } else { pulsePresets.append(value) }
        return true
    }
    func applyPreset(_ preset: PulsePreset) {
        guard preset.isValid else { return }
        pulseMode = preset.mode; pulseDuration = preset.duration
    }
    func removePreset(_ id: UUID) { pulsePresets.removeAll { $0.id == id } }

}
