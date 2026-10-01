import SwiftUI

/// The celebration on the day itself: confetti that leaves from under the arrow, fans out over the
/// popover and falls out of its bottom edge, fading over the last half second. See docs/DESIGN.md,
/// "Popover".
struct ConfettiView: View {
    /// When the burst began.
    let start: Date
    /// Where the arrow points, from the popover's left edge. The middle until it's known.
    let originX: CGFloat?

    static let duration: TimeInterval = 2.5
    private static let fade: TimeInterval = 0.5

    @State private var pieces = (0..<90).map { _ in Piece() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                context.opacity = min(max((Self.duration - elapsed) / Self.fade, 0), 1)
                let origin = CGPoint(x: originX ?? size.width / 2, y: 0)
                for piece in pieces {
                    piece.draw(in: context, at: elapsed - piece.delay, from: origin)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One piece of confetti: launched with the burst, slowed by the air, then falling at its own pace
/// with a sway, spinning, and flipping like paper.
private struct Piece {
    private enum Shape {
        case strip, square, dot, streamer
    }

    /// The system's colours, the accent among them.
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .teal, .accentColor, .purple, .pink]
    /// Points per second squared.
    private static let gravity = 420.0

    private let shape: Shape
    private let size: CGSize
    private let color = colors.randomElement()!
    /// Pieces leave over the first moment rather than all at once.
    let delay = Double.random(in: 0...0.12)
    /// Points per second, x to the right and y down.
    private let velocity: CGVector
    /// How quickly the air slows it. Light pieces fall slower.
    private let drag = Double.random(in: 2.2...4)
    private let sway = Double.random(in: 3...9)
    private let swayRate = Double.random(in: 7...15)
    private let angle = Double.random(in: 0..<(2 * .pi))
    private let spin = Double.random(in: -6...6)
    private let flipRate = Double.random(in: 6...14)
    private let phase = Double.random(in: 0..<(2 * .pi))

    init() {
        // Mostly downwards, fanning out to nearly sideways along the top.
        let direction = Double.random(in: -1.4...1.4)
        let speed = Double.random(in: 250...700)
        velocity = CGVector(dx: sin(direction) * speed, dy: cos(direction) * speed)

        switch Double.random(in: 0..<1) {
        case ..<0.58:
            shape = .strip
            size = CGSize(width: 5, height: 10)
        case ..<0.74:
            shape = .square
            size = CGSize(width: 6, height: 6)
        case ..<0.9:
            shape = .dot
            let diameter = Double.random(in: 4.5...6.5)
            size = CGSize(width: diameter, height: diameter)
        default:
            shape = .streamer
            size = CGSize(width: 2.5, height: 14)
        }
    }

    /// Draws the piece `time` seconds after it left `origin`.
    func draw(in context: GraphicsContext, at time: TimeInterval, from origin: CGPoint) {
        guard time > 0 else { return }
        // With drag, the burst slows to a steady fall: v(t) = g/k + (v₀ - g/k)e^(-kt).
        let slowed = (1 - exp(-drag * time)) / drag
        let fall = Self.gravity / drag
        let swaying = sway * min(time / 0.5, 1) * sin(swayRate * time + phase)
        let x = origin.x + velocity.dx * slowed + swaying
        let y = origin.y + fall * time + (velocity.dy - fall) * slowed

        var context = context
        context.translateBy(x: x, y: y)
        context.rotate(by: .radians(angle + spin * time))
        if shape != .dot {
            context.scaleBy(x: cos(flipRate * time + phase), y: 1)
        }
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let path = shape == .dot
            ? Path(ellipseIn: rect)
            : Path(roundedRect: rect, cornerRadius: shape == .streamer ? size.width / 2 : 1)
        context.fill(path, with: .color(color))
    }
}
