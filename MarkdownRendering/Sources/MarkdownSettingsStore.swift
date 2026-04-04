import Combine
import Foundation

public final class MarkdownSettingsStore: ObservableObject {
    static let settingsKey = "renderSettings"
    static let suiteName = "group.com.example.MarkdownQuickLook"

    private let defaults: UserDefaults

    @Published public var settings: MarkdownRenderSettings {
        didSet { save() }
    }

    public convenience init() {
        let defaults = UserDefaults(suiteName: MarkdownSettingsStore.suiteName) ?? .standard
        self.init(defaults: defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> MarkdownRenderSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let decoded = try? JSONDecoder().decode(MarkdownRenderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }
}
