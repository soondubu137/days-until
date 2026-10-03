import SwiftUI

/// The place, inside the When group while "Second time zone" is on: a search over the known
/// time zones until one is picked, then its editable name and the moment there.
struct PlaceField<Focus: Hashable>: View {
    @Binding var place: Place?
    /// The countdown's moment, shown in the place's time once one is picked.
    let moment: Date?
    let now: Date
    var focus: FocusState<Focus?>.Binding
    let searchField: Focus
    let nameField: Focus
    @State private var query = ""
    @State private var highlighted = 0

    var body: some View {
        if let place {
            picked(place)
        } else {
            search
        }
    }

    private func picked(_ place: Place) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            TextField("Place name", text: nameBinding, prompt: Text(PlaceSearch.city(of: place.timeZoneID)))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused(focus, equals: nameField)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .fieldBackground(radius: Radius.textField, isActive: focus.wrappedValue == nameField)
            if let zone = place.timeZone {
                Text(moment.map { there($0, in: zone) } ?? PlaceSearch.utcOffset(of: zone, at: now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Button {
                self.place = nil
                focus.wrappedValue = searchField
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Choose another place")
            .accessibilityLabel(Text("Choose Another Place"))
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 12)
    }

    private var search: some View {
        let results = PlaceSearch.results(for: query)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Place", text: $query, prompt: Text("Search city or time zone"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused(focus, equals: searchField)
                    .onSubmit {
                        if results.indices.contains(highlighted) { pick(results[highlighted]) }
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .fieldBackground(isActive: focus.wrappedValue == searchField)
            .padding(.horizontal, 6)

            ForEach(Array(results.enumerated()), id: \.element.identifier) { index, zone in
                resultRow(zone, isHighlighted: index == highlighted)
                    .onHover { if $0 { highlighted = index } }
                    .onTapGesture { pick(zone) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .onChange(of: query) { _ in highlighted = 0 }
        .onKeyDown { event in
            guard focus.wrappedValue == searchField, !results.isEmpty else { return false }
            switch event.key {
            case .up: highlighted = max(highlighted - 1, 0)
            case .down: highlighted = min(highlighted + 1, results.count - 1)
            default: return false
            }
            return true
        }
    }

    /// Each result shows its time now, so zones can be told apart.
    private func resultRow(_ zone: PlaceSearch.Zone, isHighlighted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.city)
                Text(verbatim: "\(zone.name) · \(PlaceSearch.utcOffset(of: zone.timeZone, at: now))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(now.formatted(Date.FormatStyle(timeZone: zone.timeZone).hour().minute()))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? Color.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func pick(_ zone: PlaceSearch.Zone) {
        place = Place(timeZoneID: zone.identifier, name: zone.city)
        query = ""
        focus.wrappedValue = nil
    }

    /// "Thu 06:00", the weekday showing when it's a different day there.
    private func there(_ moment: Date, in zone: TimeZone) -> String {
        moment.formatted(Date.FormatStyle(calendar: CountdownMath.gregorian(in: zone), timeZone: zone)
            .weekday(.abbreviated).hour().minute())
    }

    private var nameBinding: Binding<String> {
        Binding { place?.name ?? "" } set: { place?.name = $0 }
    }
}

nonisolated enum PlaceSearch {
    struct Zone: Sendable {
        let identifier: String
        let timeZone: TimeZone
        /// The city in the app's language: `Asia/Tokyo` → "Tokyo", "東京".
        let city: String
        /// The city part of the identifier, `America/New_York` → "New York", which search matches too.
        let englishCity: String
        /// The localized zone name, e.g. "Japan Standard Time".
        let name: String
        let genericName: String
    }

    static let zones: [Zone] = TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        return Zone(
            identifier: identifier,
            timeZone: zone,
            city: city(of: identifier),
            englishCity: englishCity(of: identifier),
            name: zoneName(of: zone),
            genericName: zone.localizedName(for: .generic, locale: .current) ?? ""
        )
    }

    /// The city in `locale`'s language, as the system names it: "Tokyo", "東京", "도쿄". An identifier
    /// that names no city of the system's, like America/Montreal, an alias for Toronto, keeps its own.
    static func city(of identifier: String, locale: Locale = .current) -> String {
        let english = englishCity(of: identifier)
        guard locale.language.languageCode != .english, let zone = TimeZone(identifier: identifier),
              letters(exemplarCity(of: zone, locale: Locale(identifier: "en"))) == letters(english)
        else { return english }
        return exemplarCity(of: zone, locale: locale)
    }

    /// The city part of the identifier: `America/New_York` → "New York".
    static func englishCity(of identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func exemplarCity(of zone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = "VVV"
        return formatter.string(from: Date())
    }

    /// "St. John’s" and "St_Johns" alike, as "stjohns".
    private static func letters(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter(\.isLetter)
    }

    static func zoneName(of zone: TimeZone) -> String {
        zone.localizedName(for: .standard, locale: .current) ?? zone.identifier
    }

    /// "UTC+9", "UTC−3:30", "UTC".
    static func utcOffset(of zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "UTC" }
        let minutes = abs(seconds) / 60 % 60
        let sign = seconds > 0 ? "+" : "−"
        return "UTC\(sign)\(abs(seconds) / 3_600)" + (minutes == 0 ? "" : String(format: ":%02d", minutes))
    }

    /// Cities starting with the query first, in the app's language or English, then cities containing
    /// it, then zone names containing it.
    static func results(for query: String, limit: Int = 5) -> [Zone] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func rank(_ zone: Zone) -> Int? {
            let cities = [zone.city, zone.englishCity]
            if cities.contains(where: { $0.range(of: query, options: options.union(.anchored)) != nil }) { return 0 }
            if cities.contains(where: { $0.range(of: query, options: options) != nil }) { return 1 }
            if zone.name.range(of: query, options: options) != nil
                || zone.genericName.range(of: query, options: options) != nil
                || zone.identifier.range(of: query, options: options) != nil {
                return 2
            }
            return nil
        }
        return zones
            .compactMap { zone in rank(zone).map { (zone, $0) } }
            .sorted { ($0.1, $0.0.city) < ($1.1, $1.0.city) }
            .prefix(limit)
            .map(\.0)
    }
}
