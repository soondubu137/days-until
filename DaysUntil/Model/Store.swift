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
        static let menuBarStyle = "menuBarStyle"
        static let popoverBackground = "popoverBackground"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countdown = defaults.data(forKey: Keys.countdown).flatMap {
            try? JSONDecoder().decode(Countdown.self, from: $0)
        }
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .adaptive
        popoverBackground = defaults.string(forKey: Keys.popoverBackground).flatMap(PopoverBackground.init) ?? .liquidGlass
    }

    private func saveCountdown() {
        guard let countdown, let data = try? JSONEncoder().encode(countdown) else {
            defaults.removeObject(forKey: Keys.countdown)
            return
        }
        defaults.set(data, forKey: Keys.countdown)
    }
}
