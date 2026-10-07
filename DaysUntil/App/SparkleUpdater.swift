import Sparkle

/// Sparkle, with its standard windows, for `Updates`. Scheduled updates come to the app as gentle
/// reminders rather than windows, and an update downloaded by itself is installed when the app says so.
final class SparkleUpdater: NSObject, UpdaterService {
    /// Gets what Sparkle finds. Set before `start()`.
    weak var updates: Updates?
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    func start() {
        controller.startUpdater()
    }

    private var updater: SPUUpdater { controller.updater }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    /// Taking the install over, so it can happen while the display sleeps. Sparkle still installs it if
    /// the app quits first.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        guard let updates else { return false }
        updates.sparkleWillInstallOnQuit(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }
}

extension SparkleUpdater: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Never Sparkle's window for a scheduled check, which for a menu bar app would open out of nowhere.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            updates?.sparkleFound(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updates?.sparkleGotAttention()
    }

    func standardUserDriverWillFinishUpdateSession() {
        updates?.sparkleSessionEnded()
    }
}
