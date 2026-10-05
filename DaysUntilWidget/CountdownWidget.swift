import SwiftUI
import WidgetKit

/// The countdown on the desktop, Small, Medium and Large. A glance first: a click anywhere opens the
/// popover under the menu bar item, as a click on the item does.
@main
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Countdown", provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
                // macOS draws the widget's shape, its background and the one-colour desktop look.
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetShare.url)
        }
        .configurationDisplayName(Text("Countdown", comment: "The desktop widget's name in the widget gallery."))
        .description(Text("The days left, at a glance.", comment: "The desktop widget's description in the widget gallery."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
