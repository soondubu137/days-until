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

    /// Notify Me: a notification at each milestone. Off until someone says yes, in a new install's
    /// form or in the ••• menu, so a countdown from before the switch existed starts with it off.
    @Published var notifiesAtMilestones: Bool {
        didSet { defaults.set(notifiesAtMilestones, forKey: Keys.notifiesAtMilestones) }
    }

    /// Whether a countdown has been started here, even if it's since been deleted. Only a new
    /// install opens the form by itself at launch and offers launch at login in it.
    @Published private(set) var isSetUp: Bool

    private let defaults: UserDefaults

    private enum Keys {
        static let countdown = "countdown"
        static let legacyBackup = "countdown.v1.backup"
        static let menuBarStyle = "menuBarStyle"
        static let popoverBackground = "popoverBackground"
        static let notifiesAtMilestones = "notifiesAtMilestones"
        static let isSetUp = "isSetUp"
    }

    init(defaults: UserDefaults = .standard, migrationTimeZone: TimeZone = .current) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Keys.countdown)
        let decoder = JSONDecoder()
        decoder.userInfo[Countdown.migrationTimeZoneKey] = migrationTimeZone
        var countdown = saved.flatMap { try? decoder.decode(Countdown.self, from: $0) }
        // The app's language may have changed since the place was picked.
        if let place = countdown?.place { countdown?.place = PlaceSearch.localized(place) }
        self.countdown = countdown
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .adaptive
        popoverBackground = defaults.string(forKey: Keys.popoverBackground).flatMap(PopoverBackground.init) ?? .liquidGlass
        notifiesAtMilestones = defaults.bool(forKey: Keys.notifiesAtMilestones)
        isSetUp = countdown != nil || defaults.bool(forKey: Keys.isSetUp)
        if let saved, let countdown,
           let object = try? JSONSerialization.jsonObject(with: saved) as? [String: Any], (object["version"] as? Int ?? 1) == 1,
           let migrated = try? JSONEncoder().encode(countdown) {
            if defaults.data(forKey: Keys.legacyBackup) == nil { defaults.set(saved, forKey: Keys.legacyBackup) }
            defaults.set(migrated, forKey: Keys.countdown)
        }
    }

    private func saveCountdown() {
        // Set or deleted, there's been a countdown.
        defaults.set(true, forKey: Keys.isSetUp)
        isSetUp = true
        guard let countdown, let data = try? JSONEncoder().encode(countdown) else {
            defaults.removeObject(forKey: Keys.countdown)
            return
        }
        defaults.set(data, forKey: Keys.countdown)
    }
}
