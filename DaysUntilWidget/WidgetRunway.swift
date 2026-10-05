import SwiftUI
import WidgetKit

/// The popover's runway on the desktop, counting in the finest unit that fits as the popover's
/// does. Large draws it with the popover's own geometry and month names, and Medium without the
/// month names, which it has no room for. Small has 2 pt ticks of one height ahead, ending in a
/// quiet dot. Today's mark and the
/// destination are accentable, so tinted styles keep them apart from the other ticks.
struct WidgetRunway: View {
    enum Style {
        case small
        case medium
        case large
    }

    let style: Style
    let start: Date
    let moment: Date
    let now: Date
    let icon: CountdownIcon
    /// On the day itself the finished runway and its destination take the accent colour.
    var isLit = false
    /// After the day, the destination keeps the accent.
    var isPast = false


    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { proxy in
            let track = proxy.size.width - geometry.destination - geometry.gap
            let runway = CountdownMath.runway(
                start: start, moment: moment, now: now, calendar: .local,
                maxTicks: Int(track / RunwayView.minimumTickSpacing)
            )
            ZStack(alignment: .topTrailing) {
                Canvas { context, _ in
                    drawTicks(runway, in: &context, track: track)
                }
                .widgetAccentable(isLit)
                if let now = runway.now {
                    Canvas { context, _ in
                        drawNow(at: now * track, in: &context)
                    }
                    .widgetAccentable()
                }
                destination
                    .widgetAccentable()
            }
        }
        // Large has room for the month names under the ticks.
        .frame(height: style == .large ? RunwayView.height : 28)
        .accessibilityHidden(true)
    }

    private struct Geometry {
        var tickWidth: CGFloat
        /// The bottom of every tick.
        var baseline: CGFloat
        var elapsed: CGFloat
        var ahead: CGFloat
        /// Weekends, weeks holding a first, Januaries, a day's first hour. Small has no month names
        /// to explain them, so its ticks ahead are all one height.
        var marked: CGFloat
        var destination: CGFloat
        /// Between the last tick and the destination.
        var gap: CGFloat
    }

    private var geometry: Geometry {
        switch style {
        case .small: Geometry(tickWidth: 2, baseline: 25, elapsed: 6, ahead: 11, marked: 11, destination: 6, gap: 7)
        case .medium, .large: Geometry(tickWidth: 1, baseline: 24, elapsed: 5, ahead: 8, marked: 13, destination: 22, gap: 8)
        }
    }

    private func drawTicks(_ runway: CountdownMath.Runway, in context: inout GraphicsContext, track: CGFloat) {
        let geometry = geometry
        let nowX = runway.now.map { $0 * track }
        var elapsedTicks = Path()
        var aheadTicks = Path()
        for tick in runway.ticks {
            let x = style == .small ? tick.position * track : aligned(tick.position * track)
            // Hour ticks can fall right beside now's mark, where they'd blur into it.
            if runway.scale == .hours, let nowX, abs(x - nowX) < geometry.tickWidth + 1.5 { continue }
            let height = tick.isElapsed ? geometry.elapsed : tick.isMarked ? geometry.marked : geometry.ahead
            let rect = CGRect(x: x - geometry.tickWidth / 2, y: geometry.baseline - height, width: geometry.tickWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: style == .small ? 1 : 0)
            if tick.isElapsed { elapsedTicks.addPath(path) } else { aheadTicks.addPath(path) }
        }
        context.fill(elapsedTicks, with: isLit ? .color(.accentColor) : .style(HierarchicalShapeStyle.tertiary))
        context.fill(aheadTicks, with: .style(HierarchicalShapeStyle.secondary))
        if style == .large {
            for label in RunwayView.labels(runway, track: track, context: context) {
                context.draw(label.text, at: CGPoint(x: label.x, y: RunwayView.labelTop), anchor: .topLeading)
            }
        }
    }

    private func drawNow(at x: CGFloat, in context: inout GraphicsContext) {
        let baseline = geometry.baseline
        let width: CGFloat = style == .small ? 3 : 2
        var mark = Path()
        mark.move(to: CGPoint(x: x, y: 4 + width / 2))
        mark.addLine(to: CGPoint(x: x, y: baseline - width / 2))
        context.stroke(mark, with: .color(.accentColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        let dot: CGFloat = style == .small ? 5 : 6
        context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: 0, width: dot, height: dot)), with: .color(.accentColor))
    }

    /// Small: a dot, filled with the accent once the day has come. Medium and Large: the countdown's
    /// icon in a well, as in the popover.
    @ViewBuilder
    private var destination: some View {
        switch style {
        case .small:
            Circle()
                .fill(isLit || isPast ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 6, height: 6)
                .padding(.top, 19)
        case .medium, .large:
            CountdownIconView(icon: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isLit ? Color.white : isPast ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .background(isLit ? Color.accentColor : isPast ? Color.accentSoft : Color.well, in: Circle())
                .padding(.top, 4)
        }
    }

    /// Centres a 1 pt tick on a pixel boundary, so it stays sharp.
    private func aligned(_ x: CGFloat) -> CGFloat {
        ((x - 0.5) * scale).rounded() / scale + 0.5
    }
}
