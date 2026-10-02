import Combine
import Foundation

/// The countdown and display settings, persisted to `UserDefaults`.
final class CountdownStore: ObservableObject {
    /// Nil until the user sets a date.
    @Published var countdown: Countdown? {
        didSet { saveCountdown() }
    }

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    @Published var popoverBackground: PopoverBackground {
        didSet { defaults.set(popoverBackground.rawValue, forKey: Keys.popoverBackground) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let countdown = "countdown"
        static let legacyBackup = "countdown.v1.backup"
        static let menuBarStyle = "menuBarStyle"
        static let popoverBackground = "popoverBackground"
    }

    init(defaults: UserDefaults = .standard, migrationTimeZone: TimeZone = .current) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Keys.countdown)
        let decoder = JSONDecoder()
        decoder.userInfo[Countdown.migrationTimeZoneKey] = migrationTimeZone
        countdown = saved.flatMap { try? decoder.decode(Countdown.self, from: $0) }
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .adaptive
        popoverBackground = defaults.string(forKey: Keys.popoverBackground).flatMap(PopoverBackground.init) ?? .liquidGlass
        if let saved, let countdown,
           let object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any], (object["version"] as? Int ?? 1) == 1,
           let migrated = try? JSONEncoder().encode(countdown) {
            if defaults.data(forKey: Keys.legacyBackup) == nil { defaults.set(saved, forKey: Keys.legacyBackup) }
            defaults.set(migrated, forKey: Keys.countdown)
        }
    }

    private func saveCountdown() {
        guard let countdown, let data = try? JSONEncoder().encode(countdown) else {
            defaults.removeObject(forKey: Keys.countdown)
            return
        }
        defaults.set(data, forKey: Keys.countdown)
    }
}
