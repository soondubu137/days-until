import AppKit
import Combine

/// The Updates ▸ choice in the ••• menu. Sparkle keeps it as its two settings, automatic checks and
/// automatic downloads.
enum UpdatePolicy: CaseIterable {
    case installAutomatically
    case askFirst
    case off
}

/// The one line about updates at the foot of the popover.
enum UpdateLine: Equatable {
    /// Ask Before Installing has found an update: Details or Later.
    case available(String)
    /// A downloaded update the app won't install by itself: it has waited a week for the display to
    /// sleep, or Install Automatically is no longer the choice. Install and Relaunch or Later.
    case ready(String)
    /// The first opening after an update: What's New.
    case updated(String)
}

/// What the app needs from Sparkle. `SparkleUpdater` is the real one.
@MainActor
protocol UpdaterService: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    var canCheckForUpdates: Bool { get }
    /// Shows Sparkle's window: the update it has already found, or a new check.
    func checkForUpdates()
}

/// The app's side of updating. Sparkle checks once a day. An update it downloads by itself installs
/// while the display sleeps, out of sight. One it finds in Ask Before Installing waits in a line at the
/// foot of the popover rather than in a window nobody asked for, and so does one that has waited a week
/// for the display to sleep. Sparkle's own windows open only when asked for.
@MainActor
final class Updates: ObservableObject {
    /// Later hides a line until the next daily check, as Remind Me Later does in Sparkle's window.
    static let laterInterval: TimeInterval = 24 * 60 * 60
    /// How long a downloaded update waits for the display to sleep before the line offers it, which is
    /// how long Sparkle itself waits before asking.
    static let readyAfter: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var line: UpdateLine?

    /// Whether the app can relaunch now without losing anything typed into the form.
    var canRelaunch: () -> Bool = { true }
    /// Before Sparkle shows a window, which the popover makes way for.
    var willShowSparkle: () -> Void = {}
    /// When Sparkle's session ends, with any window it showed.
    var didFinishSparkle: () -> Void = {}

    private let service: any UpdaterService
    private let now: () -> Date
    private let displaysAreAsleep: () -> Bool
    private let openURL: (URL) -> Void
    /// The update Sparkle has found and handed to the app, until it's answered.
    private var found: String?
    /// An update downloaded and checked, with Sparkle's handler that installs it and relaunches.
    private var waiting: (version: String, since: Date, install: () -> Void)?
    /// The version this launch updated to, until the popover has shown it and closed.
    private var updatedTo: String?
    private var hasShownUpdated = false
    private var hiddenUntil: Date?
    private var isPopoverShown = false
    private var subscriptions: Set<AnyCancellable> = []

    private enum Keys {
        static let lastLaunchedVersion = "lastLaunchedVersion"
    }

    init(
        service: any UpdaterService,
        defaults: UserDefaults = .standard,
        version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        now: @escaping () -> Date = Date.init,
        displaysAreAsleep: @escaping () -> Bool = { CGDisplayIsAsleep(CGMainDisplayID()) != 0 },
        displaysDidSleep: AnyPublisher<Void, Never> = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification).map { _ in }.eraseToAnyPublisher(),
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.service = service
        self.now = now
        self.displaysAreAsleep = displaysAreAsleep
        self.openURL = openURL
        if let version, let previous = defaults.string(forKey: Keys.lastLaunchedVersion),
           version.compare(previous, options: .numeric) == .orderedDescending {
            updatedTo = version
        }
        defaults.set(version, forKey: Keys.lastLaunchedVersion)
        displaysDidSleep
            .sink { [weak self] in self?.installWhileAway() }
            .store(in: &subscriptions)
        refresh()
    }

    var policy: UpdatePolicy {
        get {
            guard service.automaticallyChecksForUpdates else { return .off }
            return service.automaticallyDownloadsUpdates ? .installAutomatically : .askFirst
        }
        set {
            service.automaticallyChecksForUpdates = newValue != .off
            if newValue != .off {
                service.automaticallyDownloadsUpdates = newValue == .installAutomatically
            }
            refresh()
        }
    }

    var lastCheck: Date? { service.lastUpdateCheckDate }

    /// Sparkle can't check while an update waits to install, but the app can still answer.
    var canCheckForUpdates: Bool { waiting != nil || service.canCheckForUpdates }

    /// Check for Updates… in the ••• menu. An update that's already waiting is offered in the popover,
    /// which stays open; otherwise Sparkle checks and says what it found.
    func checkForUpdates() {
        if waiting != nil {
            waiting?.since = .distantPast
            hiddenUntil = nil
            refresh()
        } else {
            showSparkle()
        }
    }

    // MARK: The line's buttons

    func details() {
        showSparkle()
    }

    func later() {
        hiddenUntil = now().addingTimeInterval(Self.laterInterval)
        refresh()
    }

    func installAndRelaunch() {
        waiting?.install()
    }

    func whatsNew() {
        guard case .updated(let version) = line else { return }
        openURL(Self.releaseURL(for: version))
    }

    static func releaseURL(for version: String) -> URL {
        URL(string: "https://github.com/soondubu137/days-until/releases/tag/v\(version)")!
    }

    // MARK: The popover

    func popoverOpened() {
        isPopoverShown = true
        refresh()
        if case .updated = line { hasShownUpdated = true }
    }

    func popoverClosed() {
        isPopoverShown = false
        if hasShownUpdated {
            updatedTo = nil
            hasShownUpdated = false
        }
        refresh()
    }

    // MARK: From Sparkle

    /// A scheduled check found an update, which the app shows instead of Sparkle's window.
    func sparkleFound(version: String) {
        found = version
        hiddenUntil = nil
        refresh()
    }

    /// The update has Sparkle's window in front, or an answer in it.
    func sparkleGotAttention() {
        found = nil
        refresh()
    }

    func sparkleSessionEnded() {
        found = nil
        refresh()
        didFinishSparkle()
    }

    /// An update downloaded by itself is ready. Sparkle installs it when the app quits, and `install`
    /// installs it and relaunches at once.
    func sparkleWillInstallOnQuit(version: String, install: @escaping () -> Void) {
        waiting = (version, now(), install)
        hiddenUntil = nil
        if displaysAreAsleep() { installWhileAway() }
        refresh()
    }

    // MARK: -

    private func showSparkle() {
        willShowSparkle()
        service.checkForUpdates()
    }

    /// Relaunches on the waiting update, only while Install Automatically is the choice, and never
    /// while the popover is open or the form holds an edit.
    private func installWhileAway() {
        guard let waiting, policy == .installAutomatically, !isPopoverShown, canRelaunch() else { return }
        waiting.install()
    }

    func refresh() {
        let now = now()
        let isHidden = hiddenUntil.map { now < $0 } ?? false
        if let found, policy != .off, !isHidden {
            line = .available(found)
        } else if let waiting, policy != .installAutomatically || now.timeIntervalSince(waiting.since) >= Self.readyAfter, !isHidden {
            line = .ready(waiting.version)
        } else if let updatedTo {
            line = .updated(updatedTo)
        } else {
            line = nil
        }
    }
}
