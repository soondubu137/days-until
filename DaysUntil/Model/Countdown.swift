import Foundation

/// Absolute instants are the source of truth. The optional place only adds a second clock.
nonisolated struct Countdown: Codable, Hashable, Sendable {
    var name: String
    var icon: CountdownIcon
    var targetDate: Date
    var showsTime: Bool
    var place: Place?
    var startDate: Date

    init(name: String, icon: CountdownIcon, targetDate: Date, showsTime: Bool, place: Place?, startDate: Date) {
        self.name = name
        self.icon = icon
        self.targetDate = targetDate
        self.showsTime = showsTime
        self.place = place
        self.startDate = startDate
    }

    private enum CodingKeys: String, CodingKey {
        case version, name, icon, targetDate, showsTime, place, startDate
        case date, time, countingFrom // Version 1, before absolute instants were stored.
    }

    /// Used only when resolving old, floating data. New data is independent of this zone.
    static let migrationTimeZoneKey = CodingUserInfoKey(rawValue: "countdownMigrationTimeZone")!

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        icon = try values.decode(CountdownIcon.self, forKey: .icon)
        place = try values.decodeIfPresent(Place.self, forKey: .place)
        let version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        switch version {
        case 2:
            targetDate = try values.decode(Date.self, forKey: .targetDate)
            startDate = try values.decode(Date.self, forKey: .startDate)
            showsTime = try values.decode(Bool.self, forKey: .showsTime)
        case 1:
            let local = decoder.userInfo[Self.migrationTimeZoneKey] as? TimeZone ?? .current
            let day = try values.decode(CalendarDay.self, forKey: .date)
            let time = try values.decodeIfPresent(TimeOfDay.self, forKey: .time)
            let from = try values.decode(CalendarDay.self, forKey: .countingFrom)
            // Preserve the old app's effective instant, including its DST normalization policy.
            // A legacy place used to define the input zone; it becomes display-only after migration.
            let zone = place?.timeZone ?? local
            targetDate = time.map { CountdownMath.date(day, at: $0, in: zone) }
                ?? CountdownMath.startOfDay(day, in: zone)
            startDate = CountdownMath.startOfDay(from, in: local)
            showsTime = time != nil
        default:
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported countdown version.")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(2, forKey: .version)
        try values.encode(name, forKey: .name)
        try values.encode(icon, forKey: .icon)
        try values.encode(targetDate, forKey: .targetDate)
        try values.encode(startDate, forKey: .startDate)
        try values.encode(showsTime, forKey: .showsTime)
        try values.encodeIfPresent(place, forKey: .place)
    }
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

    var emoji: String? {
        if case .emoji(let emoji) = self { emoji } else { nil }
    }
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

/// What the popover is drawn on. Only macOS 26 and later offer the choice; before that the popover
/// is always solid, whatever is saved, so upgrading later brings Liquid Glass back as the default.
nonisolated enum PopoverBackground: String, Codable, CaseIterable, Sendable {
    case liquidGlass
    case solid

    /// What the popover uses on this Mac.
    static func effective(_ saved: PopoverBackground) -> PopoverBackground {
        if #available(macOS 26, *) { saved } else { .solid }
    }
}
