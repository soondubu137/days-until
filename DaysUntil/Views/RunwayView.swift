import SwiftUI

/// The whole journey at a glance: a tick per day (or week, or hour) from Counting from to the day,
/// taller on weekends, today in the accent colour, and the countdown's icon waiting at the end.
struct RunwayView: View {
    let runway: CountdownMath.Runway
    let icon: CountdownIcon
    /// On the day itself the finished runway and its destination take the accent colour.
    var isLit = false
    /// After the day, the destination keeps a quieter accent.
    var isPast = false

    static let height: CGFloat = 42
    private static let destination: CGFloat = 22
    /// Between the last tick and the destination.
    private static let gap: CGFloat = 8
    /// The bottom of every tick.
    private static let baseline: CGFloat = 24
    private static let labelTop: CGFloat = 30

    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                draw(in: &context, width: size.width - Self.destination - Self.gap)
            }
            destination
                .offset(y: 4)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }

    private var destination: some View {
        CountdownIconView(icon: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isLit ? Color.white : isPast ? Color.accentColor : Color.secondary)
            .frame(width: Self.destination, height: Self.destination)
            .background(isLit ? Color.accentColor : isPast ? Color.accentSoft : Color.well, in: Circle())
    }

    private func draw(in context: inout GraphicsContext, width track: CGFloat) {
        let elapsed = isLit ? Color.accentColor : Color(nsColor: .tertiaryLabelColor)
        let ahead = Color(nsColor: .secondaryLabelColor)
        let nowX = runway.now.map { $0 * track }

        var elapsedTicks = Path()
        var aheadTicks = Path()
        for tick in runway.ticks {
            let x = aligned(tick.position * track)
            // Hour ticks can fall right beside now's mark, where they'd blur into it.
            if runway.scale == .hours, let nowX, abs(x - nowX) < 2.5 { continue }
            let height: CGFloat = tick.isElapsed ? 5 : tick.isMarked ? 13 : 8
            let path = Path { $0.addRect(CGRect(x: x - 0.5, y: Self.baseline - height, width: 1, height: height)) }
            if tick.isElapsed { elapsedTicks.addPath(path) } else { aheadTicks.addPath(path) }
        }
        context.fill(elapsedTicks, with: .color(elapsed))
        context.fill(aheadTicks, with: .color(ahead))

        if let nowX {
            var mark = Path()
            mark.move(to: CGPoint(x: nowX, y: 5))
            mark.addLine(to: CGPoint(x: nowX, y: Self.baseline))
            context.stroke(mark, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: nowX - 3, y: 1, width: 6, height: 6)), with: .color(.accentColor))
        }

        for label in labels(track: track, context: context) {
            context.draw(label.text, at: CGPoint(x: label.x, y: Self.labelTop), anchor: .topLeading)
        }
    }

    /// Month names that fit without crowding: every month when there's room, otherwise every second,
    /// third or sixth. The start's month shows too, when it isn't squeezed by the first of those.
    private func labels(track: CGFloat, context: GraphicsContext) -> [(x: CGFloat, text: GraphicsContext.ResolvedText)] {
        let calendar = Calendar.local
        func resolve(_ string: String) -> GraphicsContext.ResolvedText {
            context.resolve(Text(string).font(.micro).foregroundColor(Color(nsColor: .secondaryLabelColor)))
        }
        func placed(_ label: CountdownMath.Runway.Label, _ string: String) -> (x: CGFloat, text: GraphicsContext.ResolvedText) {
            let text = resolve(string)
            let width = text.measure(in: CGSize(width: 100, height: 20)).width
            return (min(max(label.position * track - 1, 0), track - width), text)
        }

        guard runway.scale != .hours else {
            let style = Date.FormatStyle(timeZone: calendar.timeZone).hour()
            return runway.labels.map { placed($0, $0.date.formatted(style)) }
        }

        let crossesYears = Set(runway.labels.map { calendar.component(.year, from: $0.date) }).count > 1
        func name(_ date: Date) -> String {
            if crossesYears, calendar.component(.month, from: date) == 1 {
                return date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).year())
            }
            return date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated))
        }

        let monthWidth = track * 30.44 / Double(max(runway.days, 1))
        let stride = [1, 2, 3, 6, 12].first { CGFloat($0) * monthWidth >= 40 } ?? 12
        var result = runway.labels.dropFirst()
            .filter { (calendar.component(.month, from: $0.date) - 1) % stride == 0 }
            .map { placed($0, name($0.date)) }
        if let start = runway.labels.first {
            let label = placed(start, name(start.date))
            let width = label.text.measure(in: CGSize(width: 100, height: 20)).width
            if result.first.map({ $0.x >= label.x + width + 12 }) ?? true {
                result.insert(label, at: 0)
            }
        }
        return result
    }

    /// Centres a 1 pt tick on a pixel boundary, so it stays sharp.
    private func aligned(_ x: CGFloat) -> CGFloat {
        ((x - 0.5) * scale).rounded() / scale + 0.5
    }
}
