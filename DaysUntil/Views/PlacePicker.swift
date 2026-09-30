import SwiftUI

/// Searches the known time zones by city and zone name. Once one is picked, its display name is editable.
struct PlacePicker: View {
    @Binding var place: Place?
    let now: Date
    @State private var query = ""

    var body: some View {
        if let place {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    TextField("Place name", text: nameBinding, prompt: Text(PlaceSearch.city(of: place.timeZoneID)))
                        .labelsHidden()
                    Button {
                        self.place = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Choose another place")
                }
                if let zone = place.timeZone {
                    Text("\(PlaceSearch.zoneName(of: zone)) · \(PlaceSearch.utcOffset(of: zone, at: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            let results = PlaceSearch.results(for: query)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Place", text: $query, prompt: Text("Search city or time zone"))
                    .labelsHidden()
                    .onSubmit {
                        if let first = results.first { pick(first) }
                    }
                ForEach(results, id: \.identifier) { zone in
                    Button {
                        pick(zone)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(zone.city)
                            Text("\(zone.name) · \(PlaceSearch.utcOffset(of: zone.timeZone, at: now))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ zone: PlaceSearch.Zone) {
        place = Place(timeZoneID: zone.identifier, name: zone.city)
        query = ""
    }

    private var nameBinding: Binding<String> {
        Binding { place?.name ?? "" } set: { place?.name = $0 }
    }
}

nonisolated enum PlaceSearch {
    struct Zone: Sendable {
        let identifier: String
        let timeZone: TimeZone
        /// The city part of the identifier: `America/New_York` → "New York".
        let city: String
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
            name: zoneName(of: zone),
            genericName: zone.localizedName(for: .generic, locale: .current) ?? ""
        )
    }

    static func city(of identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
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

    /// Cities starting with the query first, then cities containing it, then zone names containing it.
    static func results(for query: String, limit: Int = 5) -> [Zone] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func rank(_ zone: Zone) -> Int? {
            if zone.city.range(of: query, options: options.union(.anchored)) != nil { return 0 }
            if zone.city.range(of: query, options: options) != nil { return 1 }
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
