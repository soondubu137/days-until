import Foundation

/// The one date the app counts down to. See `docs/DESIGN.md`, "The countdown".
///
/// The date and time are kept as components and only resolved to an absolute moment by `CountdownMath`,
/// so a floating countdown moves with the Mac's time zone and a pinned one stays put.
nonisolated struct Countdown: Codable, Hashable, Sendable {
    var name: String
    var icon: CountdownIcon
    var date: CalendarDay
    /// Without an exact time, the countdown runs to the start of the day.
    var time: TimeOfDay?
    /// Without a place, the date and time are read in the Mac's current time zone.
    var place: Place?
    /// Start of the progress bar, read in the Mac's current time zone.
    var countingFrom: CalendarDay
}

/// A Gregorian year, month and day, with no time zone attached.
nonisolated struct CalendarDay: Codable, Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int
}

nonisolated struct TimeOfDay: Codable, Hashable, Sendable {
    var hour: Int
    var minute: Int
}

/// A time zone plus the name the user calls it by, e.g. `Asia/Shanghai` shown as "Home".
nonisolated struct Place: Codable, Hashable, Sendable {
    var timeZoneID: String
    var name: String

    var timeZone: TimeZone? { TimeZone(identifier: timeZoneID) }
}

nonisolated enum CountdownIcon: Hashable, Sendable {
    case symbol(String)
    case emoji(String)

    static let presetSymbols = [
        "house", "airplane", "suitcase", "heart", "gift", "graduationcap", "star", "calendar",
    ]
    static let `default` = CountdownIcon.symbol("house")
}

// Stored as `{"symbol": "house"}` or `{"emoji": "🎄"}`.
extension CountdownIcon: Codable {
    private enum CodingKeys: String, CodingKey {
        case symbol, emoji
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .symbol) {
            self = .symbol(name)
        } else {
            self = .emoji(try container.decode(String.self, forKey: .emoji))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name): try container.encode(name, forKey: .symbol)
        case .emoji(let emoji): try container.encode(emoji, forKey: .emoji)
        }
    }
}

nonisolated enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    /// More precision as the moment nears: days, then days and hours, then a seconds clock.
    case adaptive
    case daysOnly
    case daysAndHours
    case alwaysSeconds
    /// Useful when the notch would hide the item.
    case iconOnly
}
