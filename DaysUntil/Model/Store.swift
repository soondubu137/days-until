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

    /// The countdown whose day had its confetti, so it plays once, even across relaunches.
    private var celebrated: Countdown? {
        didSet { defaults.set(celebrated.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.celebrated) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let countdown = "countdown"
        static let menuBarStyle = "menuBarStyle"
        static let popoverBackground = "popoverBackground"
        static let celebrated = "celebrated"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countdown = defaults.data(forKey: Keys.countdown).flatMap {
            try? JSONDecoder().decode(Countdown.self, from: $0)
        }
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .adaptive
        popoverBackground = defaults.string(forKey: Keys.popoverBackground).flatMap(PopoverBackground.init) ?? .liquidGlass
        celebrated = defaults.data(forKey: Keys.celebrated).flatMap {
            try? JSONDecoder().decode(Countdown.self, from: $0)
        }
    }

    /// Whether `countdown`'s day has had its confetti. Only the moment counts: a new name or icon
    /// doesn't celebrate again, a new date, time or place does.
    func hasCelebrated(_ countdown: Countdown) -> Bool {
        guard let celebrated else { return false }
        return celebrated.date == countdown.date && celebrated.time == countdown.time
            && celebrated.place?.timeZoneID == countdown.place?.timeZoneID
    }

    func markCelebrated(_ countdown: Countdown) {
        celebrated = countdown
    }

    private func saveCountdown() {
        guard let countdown, let data = try? JSONEncoder().encode(countdown) else {
            defaults.removeObject(forKey: Keys.countdown)
            return
        }
        defaults.set(data, forKey: Keys.countdown)
    }
}
