import AppKit
import AVFoundation
import SwiftUI

// The intro video: the menu bar item, the popover opening, the count running down to the day, and
// the confetti. The popover is the app's own CountdownView, drawn at each frame's moment; the
// desktop around it is drawn here. Built and run by scripts/make-intro-video.sh.
//
// Usage: intro <repo root> <output.mp4> [--stills <seconds,…>]
//        intro <repo root> <folder> --frames <width in pixels>
// With --stills it writes PNGs of those moments next to the output instead of the video. With
// --frames it writes every frame as a PNG that wide, for the README's WebP.

_ = NSApplication.shared

let arguments = CommandLine.arguments
let root = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let stills = arguments.firstIndex(of: "--stills").map { arguments[$0 + 1].split(separator: ",").compactMap { Double($0) } }
let framesWidth = arguments.firstIndex(of: "--frames").map { CGFloat(Double(arguments[$0 + 1])!) }

// MARK: - The countdown

let calendar = Calendar.local

func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let countdown = Countdown(
    name: "Going home", icon: .symbol("house"), targetDate: local(2026, 11, 18, 14, 0), showsTime: true,
    place: Place(timeZoneID: "Asia/Shanghai", name: "Shanghai"), startDate: local(2026, 9, 23, 0, 0)
)
let target = countdown.targetDate
/// The Mac's clock as the desktop first appears.
let opening = local(2026, 10, 1, 9, 41)

// MARK: - Timeline, in seconds

let fps = 30
let duration = 17.1

enum Cue {
    static let titleOut = 2.2           // the title card gives way to the menu bar, zoomed in
    static let zoomOut = 5.4            // back to the whole desktop
    static let cursorIn = 6.0
    static let click = 6.9              // the popover opens on mouse down
    static let fastForward = 9.6        // the clock runs on to the moment
    static let reached = fastForward + 4.5
    static let titleIn = 16.4           // back to the title card, which the video loops into
}

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func progress(_ t: Double, _ from: Double, _ to: Double) -> Double { clamp((t - from) / (to - from)) }
func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
func easeInOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }

/// Time left at `t`. Real time until the fast-forward, which then spends about a second on each
/// rung of the ladder: days, days and hours, and the clock, slowing for the last seconds.
func remaining(at t: Double) -> TimeInterval {
    let week = CountdownMath.week, day = CountdownMath.day
    let atStart = target.timeIntervalSince(opening) - (Cue.fastForward - Cue.titleOut)
    let days = Cue.fastForward + 1.1, hours = days + 0.9, seconds = hours + 2.0
    switch t {
    case ..<Cue.fastForward: return target.timeIntervalSince(opening) - (t - Cue.titleOut)
    case ..<days: return exp(lerp(log(atStart), log(week), progress(t, Cue.fastForward, days)))
    case ..<hours: return exp(lerp(log(week), log(day), progress(t, days, hours)))
    case ..<seconds: return exp(log(day) * pow(1 - progress(t, hours, seconds), 2))
    case ..<Cue.reached: return 1 - progress(t, seconds, Cue.reached)
    default: return -(t - Cue.reached)
    }
}

func now(at t: Double) -> Date { target - remaining(at: t) }

// MARK: - Layout, in points

let canvas = CGSize(width: 800, height: 500)
let scale: CGFloat = 2.4
let barHeight: CGFloat = 26
let ink = Color.black.opacity(0.85)
let menuFont = NSFont.systemFont(ofSize: 13, weight: .medium)
/// A ticking clock's digits are fixed-width, so the seconds don't shift what's beside them.
let clockFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
let houseWidth = NSImage(systemSymbolName: "house", accessibilityDescription: nil)!
    .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))!.size.width

func width(_ string: String, _ font: NSFont = menuFont) -> CGFloat {
    NSAttributedString(string: string, attributes: [.font: font]).size().width
}

/// The menu bar clock at `moment`.
func clockText(at moment: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "EEE MMM d  h:mm a"
    return formatter.string(from: moment)
}

/// What Days Until shows beside its icon at `moment`.
func itemText(at moment: Date) -> CountdownMath.MenuBarText {
    CountdownMath.menuBarDisplay(moment: target, style: .adaptive, now: moment, calendar: calendar).text
}

/// The right side of the menu bar, laid out from the clock leftwards, so the items move over as
/// the clock's text and ours change width.
struct Bar {
    static let clockRight: CGFloat = canvas.width - 12
    static let spacing: CGFloat = 18
    /// System items and the width each takes, right to left.
    static let items: [(symbol: String, width: CGFloat)] = [("switch.2", 16), ("wifi", 17), ("battery.100percent", 27)]

    let clock: String
    let text: CountdownMath.MenuBarText
    let clockWidth: CGFloat
    let itemCentres: [CGFloat]
    /// The Days Until item's right edge and centre.
    let ourRight: CGFloat
    let ourCentre: CGFloat

    init(at moment: Date) {
        clock = clockText(at: moment)
        text = itemText(at: moment)
        clockWidth = width(clock, clockFont)
        var x = Self.clockRight - clockWidth - Self.spacing
        itemCentres = Self.items.map { item in
            defer { x -= item.width + Self.spacing }
            return x - item.width / 2
        }
        ourRight = x
        let words: CGFloat =
            switch text {
            case .remaining(let words):
                words.split(separator: " ").map { width(String($0), $0.contains(":") ? clockFont : menuFont) }.reduce(0, +)
                    + CGFloat(words.split(separator: " ").count - 1) * 3
            case .today: width("Today") + 5
            case .iconOnly: 0
            }
        ourCentre = ourRight - (houseWidth + 5 + words) / 2
    }
}

let popoverWidth: CGFloat = 340
let arrowHeight: CGFloat = 11
/// The popover stays where it opened; its arrow follows the item.
let popoverLeft = Bar(at: opening).ourCentre - popoverWidth / 2
let popoverTop = barHeight + 2 + arrowHeight

// MARK: - Frame

struct Frame: View {
    let t: Double

    var body: some View {
        let moment = now(at: t)
        let bar = Bar(at: moment)
        // The camera: zoomed in on the right of the menu bar, then out to the whole desktop.
        let out = easeInOut(progress(t, Cue.zoomOut, Cue.zoomOut + 1))
        let zoom = lerp(2, 1, out)
        let focus = CGPoint(x: bar.ourCentre, y: barHeight / 2)
        let zoomedIn = CGPoint(x: canvas.width - 40 - (Bar.clockRight - focus.x) * 2, y: 52)
        let onScreen = CGPoint(x: lerp(zoomedIn.x, focus.x, out), y: lerp(zoomedIn.y, focus.y, out))
        let fadeIn = progress(t, Cue.titleOut + 0.2, Cue.titleOut + 0.7)
        let fadeOut = 1 - progress(t, Cue.titleIn, Cue.titleIn + 0.35)

        ZStack(alignment: .topLeading) {
            Wallpaper()

            Desktop(t: t, moment: moment, bar: bar)
                .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(x: onScreen.x - focus.x * zoom, y: onScreen.y - focus.y * zoom)
                .opacity(fadeIn * fadeOut)

            Captions(t: t)
                .opacity(fadeOut)

            TitleCard()
                .scaleEffect(lerp(1, 1.04, progress(t, Cue.titleOut, Cue.titleOut + 0.6)))
                .opacity(1 - progress(t, Cue.titleOut, Cue.titleOut + 0.5) + progress(t, Cue.titleIn + 0.25, duration))
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

/// A plain light gray, a shade darker towards the bottom.
struct Wallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.98, green: 0.98, blue: 0.99), Color(red: 0.93, green: 0.93, blue: 0.94)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: canvas.width, height: canvas.height)
    }
}

// MARK: - Desktop

struct Desktop: View {
    let t: Double
    let moment: Date
    let bar: Bar

    var body: some View {
        let isOpen = t >= Cue.click
        ZStack(alignment: .topLeading) {
            MenuBar(bar: bar, isHighlighted: isOpen)
            if isOpen {
                Popover(t: t, moment: moment, arrowX: bar.ourCentre - popoverLeft)
                    .offset(x: popoverLeft, y: popoverTop)
                    .opacity(progress(t, Cue.click, Cue.click + 0.1))
            }
            Cursor(t: t, item: bar.ourCentre)
        }
    }
}

struct MenuBar: View {
    let bar: Bar
    let isHighlighted: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 20) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.trailing, 2)
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) {
                    Text($0).font(.system(size: 13))
                }
            }
            .frame(height: barHeight)
            .offset(x: 20)

            ForEach(Array(Bar.items.enumerated()), id: \.offset) { index, item in
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: item.width, height: barHeight)
                    .offset(x: bar.itemCentres[index] - item.width / 2)
            }

            Text(bar.clock)
                .font(Font(clockFont))
                .frame(width: bar.clockWidth + 20, height: barHeight, alignment: .trailing)
                .offset(x: Bar.clockRight - bar.clockWidth - 20)

            OurItem(text: bar.text, isHighlighted: isHighlighted)
                .frame(width: 200, height: barHeight, alignment: .trailing)
                .offset(x: bar.ourRight - 200)
        }
        .foregroundStyle(ink)
    }
}

/// The Days Until item, with the text the app shows.
struct OurItem: View {
    let text: CountdownMath.MenuBarText
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "house")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(text == .today ? Color.accentColor : ink)
            switch text {
            case .remaining(let words):
                // Units closer than words; a ticking clock in fixed-width digits.
                HStack(spacing: 3) {
                    ForEach(Array(words.split(separator: " ").enumerated()), id: \.offset) { _, unit in
                        Text(unit).font(Font(unit.contains(":") ? clockFont : menuFont))
                    }
                }
            case .today:
                Text("Today")
            case .iconOnly:
                EmptyView()
            }
        }
        .font(Font(menuFont))
        .background {
            if isHighlighted {
                Capsule()
                    .fill(Color.black.opacity(0.1))
                    .padding(.horizontal, -8)
                    .frame(height: 22)
            }
        }
    }
}

struct Popover: View {
    let t: Double
    let moment: Date
    let arrowX: CGFloat

    var body: some View {
        CountdownView(countdown: countdown, now: moment, makeMenu: { NSMenu() }, onStartOver: {})
            .frame(width: popoverWidth)
            .environment(\.popoverBackground, .liquidGlass)
            .background {
                GeometryReader { geometry in
                    let shape = PopoverShape(arrowX: arrowX)
                    ZStack {
                        shape.fill(Color.white.opacity(0.7))
                            .shadow(color: .black.opacity(0.16), radius: 26, y: 12)
                        shape.stroke(Color.black.opacity(0.07), lineWidth: 1)
                        shape.inset(by: 0.75).stroke(Color.white.opacity(0.9), lineWidth: 1)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height + arrowHeight)
                    .offset(y: -arrowHeight)
                }
            }
            .overlay {
                if t >= Cue.reached {
                    GeometryReader { geometry in
                        Confetti(elapsed: t - Cue.reached, origin: CGPoint(x: arrowX, y: 2))
                            .frame(width: geometry.size.width, height: geometry.size.height + arrowHeight)
                            .clipShape(PopoverShape(arrowX: arrowX))
                            .offset(y: -arrowHeight)
                    }
                }
            }
    }
}

/// The popover's outline: a rounded rectangle under an arrow that points up at the item.
struct PopoverShape: InsettableShape {
    let arrowX: CGFloat
    var inset: CGFloat = 0
    let radius: CGFloat = 26
    let arrowWidth: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let top = r.minY + arrowHeight
        let radius = radius - inset
        let half = arrowWidth / 2 - inset
        let tip = r.minY
        var path = Path()
        path.move(to: CGPoint(x: r.minX + radius, y: top))
        path.addLine(to: CGPoint(x: arrowX - half, y: top))
        path.addCurve(to: CGPoint(x: arrowX - 3, y: tip + 1.4),
                      control1: CGPoint(x: arrowX - half + 8, y: top), control2: CGPoint(x: arrowX - 6, y: tip + 4))
        path.addQuadCurve(to: CGPoint(x: arrowX + 3, y: tip + 1.4), control: CGPoint(x: arrowX, y: tip - 0.6))
        path.addCurve(to: CGPoint(x: arrowX + half, y: top),
                      control1: CGPoint(x: arrowX + 6, y: tip + 4), control2: CGPoint(x: arrowX + half - 8, y: top))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: top), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: top), radius: radius)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: top), tangent2End: CGPoint(x: r.minX + radius, y: top), radius: radius)
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> PopoverShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The pointer: in from the side, onto the item, a click, then away.
struct Cursor: View {
    static let image = NSCursor.arrow.image
    static let hotSpot = NSCursor.arrow.hotSpot

    let t: Double
    let item: CGFloat

    var body: some View {
        let start = CGPoint(x: item + 150, y: 330)
        let onItem = CGPoint(x: item + 3, y: barHeight / 2 + 2)
        let away = CGPoint(x: item + 240, y: 250)
        let arrive = easeInOut(progress(t, Cue.cursorIn, Cue.click - 0.05))
        let leave = easeInOut(progress(t, Cue.click + 0.35, Cue.click + 1.1))
        let x = lerp(lerp(start.x, onItem.x, arrive), away.x, leave)
        let y = lerp(lerp(start.y, onItem.y, arrive), away.y, leave)
        let pressed = t >= Cue.click - 0.04 && t < Cue.click + 0.1
        let opacity = progress(t, Cue.cursorIn, Cue.cursorIn + 0.2) * (1 - progress(t, Cue.click + 0.8, Cue.click + 1.1))
        Image(nsImage: Self.image)
            .scaleEffect(pressed ? 0.9 : 1, anchor: UnitPoint(x: Self.hotSpot.x / Self.image.size.width, y: Self.hotSpot.y / Self.image.size.height))
            .offset(x: x - Self.hotSpot.x, y: y - Self.hotSpot.y)
            .opacity(opacity)
    }
}

// MARK: - Confetti

/// The app's confetti (ConfettiView), with its pieces drawn from a fixed seed so every render matches.
struct Confetti: View {
    let elapsed: TimeInterval
    let origin: CGPoint

    static let pieces: [ConfettiPiece] = {
        var random = SplitMix(seed: 20261220)
        return (0..<90).map { _ in ConfettiPiece(using: &random) }
    }()

    var body: some View {
        Canvas { context, _ in
            context.opacity = clamp((2.5 - elapsed) / 0.5)
            for piece in Self.pieces {
                piece.draw(in: context, at: elapsed - piece.delay, from: origin)
            }
        }
    }
}

struct SplitMix: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct ConfettiPiece {
    enum Shape { case strip, square, dot, streamer }

    static let colors: [Color] = [.red, .orange, .yellow, .green, .teal, .accentColor, .purple, .pink]
    static let gravity = 420.0

    let shape: Shape
    let size: CGSize
    let color: Color
    let delay: Double
    let velocity: CGVector
    let drag, sway, swayRate, angle, spin, flipRate, phase: Double

    init(using random: inout SplitMix) {
        color = Self.colors.randomElement(using: &random)!
        delay = .random(in: 0...0.12, using: &random)
        drag = .random(in: 2.2...4, using: &random)
        sway = .random(in: 3...9, using: &random)
        swayRate = .random(in: 7...15, using: &random)
        angle = .random(in: 0..<(2 * .pi), using: &random)
        spin = .random(in: -6...6, using: &random)
        flipRate = .random(in: 6...14, using: &random)
        phase = .random(in: 0..<(2 * .pi), using: &random)
        let direction = Double.random(in: -1.4...1.4, using: &random)
        let speed = Double.random(in: 250...700, using: &random)
        velocity = CGVector(dx: sin(direction) * speed, dy: cos(direction) * speed)
        switch Double.random(in: 0..<1, using: &random) {
        case ..<0.58: shape = .strip; size = CGSize(width: 5, height: 10)
        case ..<0.74: shape = .square; size = CGSize(width: 6, height: 6)
        case ..<0.9:
            shape = .dot
            let diameter = Double.random(in: 4.5...6.5, using: &random)
            size = CGSize(width: diameter, height: diameter)
        default: shape = .streamer; size = CGSize(width: 2.5, height: 14)
        }
    }

    func draw(in context: GraphicsContext, at time: TimeInterval, from origin: CGPoint) {
        guard time > 0 else { return }
        let slowed = (1 - exp(-drag * time)) / drag
        let fall = Self.gravity / drag
        let swaying = sway * min(time / 0.5, 1) * sin(swayRate * time + phase)
        var context = context
        context.translateBy(x: origin.x + velocity.dx * slowed + swaying, y: origin.y + fall * time + (velocity.dy - fall) * slowed)
        context.rotate(by: .radians(angle + spin * time))
        if shape != .dot {
            context.scaleBy(x: cos(flipRate * time + phase), y: 1)
        }
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let path = shape == .dot ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: shape == .streamer ? size.width / 2 : 1)
        context.fill(path, with: .color(color))
    }
}

// MARK: - Words

struct Captions: View {
    let t: Double

    private enum Position { case centre, left }

    private static let lines: [(text: String, from: Double, to: Double, place: Position)] = [
        ("See how many days are left at a glance.", Cue.titleOut + 0.6, Cue.zoomOut, .centre),
        ("Click it to see how\nfar you’ve come.", Cue.click + 0.2, Cue.fastForward - 0.1, .left),
        ("It gets more precise\nas the day nears.", Cue.fastForward, Cue.reached - 0.2, .left),
        ("And on the day,\nit celebrates.", Cue.reached, duration, .left),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.lines.enumerated()), id: \.offset) { _, line in
                let shown = easeOut(progress(t, line.from, line.from + 0.4))
                let opacity = min(shown, 1 - progress(t, line.to - 0.3, line.to))
                if opacity > 0 {
                    caption(line.text, place: line.place)
                        .offset(y: (1 - shown) * 10)
                        .opacity(opacity)
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func caption(_ text: String, place: Position) -> some View {
        let label = Text(text).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
        switch place {
        case .centre:
            label
                .font(.system(size: 34))
                .multilineTextAlignment(.center)
                .frame(width: canvas.width, height: canvas.height)
                .offset(y: 40)
        case .left:
            label
                .font(.system(size: 28))
                .lineSpacing(2)
                .fixedSize()
                .frame(width: popoverLeft - 44, alignment: .leading)
                .frame(height: canvas.height)
                .offset(x: 44, y: 10)
        }
    }
}

struct TitleCard: View {
    static let icon = NSImage(contentsOf: root.appending(path: "design/assets/04-app-icon/days-until-icon-1024.png"))!

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: Self.icon)
                .resizable()
                .frame(width: 190, height: 190)
            Wordmark()
                .fill(Color(red: 0.114, green: 0.114, blue: 0.122))
                .frame(width: Wordmark.width(capHeight: 40), height: 40)
                .padding(.top, 8)
            Text("A quiet countdown to the day you are waiting for.")
                .font(.system(size: 19))
                .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.62))
                .padding(.top, 22)
        }
        .frame(width: canvas.width, height: canvas.height)
        .offset(y: -6)
    }
}

/// "Days Until" in the logo's lettering: the outlines scripts/make-icons.py draws the wordmark from.
struct Wordmark: Shape {
    private static let left = 73.2, right = 4646.2, capHeight = 727.5

    static func width(capHeight cap: CGFloat) -> CGFloat { (right - left) * cap / capHeight }

    private static let outline: Path = {
        let script = try! String(contentsOf: root.appending(path: "scripts/make-icons.py"), encoding: .utf8)
        let start = script.range(of: "WORDMARK = (\n    \"")!.upperBound
        let data = script[start..<script.range(of: "\"", range: start..<script.endIndex)!.lowerBound]
        var path = Path()
        var command = "M"
        var numbers: [Double] = []
        for token in data.matches(of: try! Regex("[MLQZ]|-?[0-9.]+")).map({ String(data[$0.range]) }) {
            if let number = Double(token) {
                numbers.append(number)
            } else {
                command = token
                if command == "Z" { path.closeSubpath() }
            }
            switch (command, numbers.count) {
            case ("M", 2): path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
            case ("L", 2): path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
            case ("Q", 4): path.addQuadCurve(to: CGPoint(x: numbers[2], y: numbers[3]), control: CGPoint(x: numbers[0], y: numbers[1]))
            default: continue
            }
            numbers = []
        }
        return path
    }()

    func path(in rect: CGRect) -> Path {
        let s = rect.height / Self.capHeight
        return Self.outline.applying(CGAffineTransform(translationX: rect.minX - Self.left * s, y: rect.maxY).scaledBy(x: s, y: s))
    }
}

// MARK: - Rendering

let frameCount = Int((duration * Double(fps)).rounded())

func render(_ t: Double, scale: CGFloat = scale) -> CGImage {
    let renderer = ImageRenderer(content: Frame(t: t))
    renderer.scale = scale
    renderer.isOpaque = true
    return renderer.cgImage!
}

MainActor.assumeIsolated {
    if let stills {
        for t in stills {
            let rep = NSBitmapImageRep(cgImage: render(t))
            let url = output.deletingPathExtension().appendingPathExtension("\(t).png")
            try! rep.representation(using: .png, properties: [:])!.write(to: url)
            print(url.path)
        }
        return
    }

    if let framesWidth {
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for index in 0..<frameCount {
            let rep = NSBitmapImageRep(cgImage: render(Double(index) / Double(fps), scale: framesWidth / canvas.width))
            try! rep.representation(using: .png, properties: [:])!.write(to: output.appending(path: String(format: "%04d.png", index)))
        }
        return
    }

    let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
    try? FileManager.default.removeItem(at: output)
    let writer = try! AVAssetWriter(outputURL: output, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: size.width,
        AVVideoHeightKey: size.height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 8_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for index in 0..<frameCount {
        let image = render(Double(index) / Double(fps))
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixels), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.draw(image, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
        if index % 30 == 0 { print("frame \(index)/\(frameCount)") }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    print(writer.status == .completed ? output.path : "failed: \(String(describing: writer.error))")
}
