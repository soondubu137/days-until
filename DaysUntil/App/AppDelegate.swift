import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // A test host must not migrate or change the user's real countdown on launch.
        let defaults = isTesting ? UserDefaults(suiteName: "DaysUntilTests.Host")! : .standard
        if isTesting { defaults.removePersistentDomain(forName: "DaysUntilTests.Host") }
        let store = CountdownStore(defaults: defaults)
        let statusItem = StatusItemController(store: store)
        self.statusItem = statusItem
        NSApp.mainMenu = Self.makeMainMenu(statusItem: statusItem)

        // On first launch, open straight to the edit form. Not once a countdown has been deleted,
        // when the menu bar item asks for a date itself, nor while unit tests run in the app.
        if !store.isSetUp, !isTesting {
            statusItem.showPopoverOnceInPlace()
        }
    }

    /// The menu bar is never shown, since the app has no Dock icon, but the popover still needs the
    /// shortcuts that come from these items' key equivalents: ⌘E and ⌘Q from the ••• menu, ⌘W for the
    /// About panel, and the standard editing ones for the text fields.
    private static func makeMainMenu(statusItem: StatusItemController) -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Edit Countdown…", action: #selector(StatusItemController.editCountdown), keyEquivalent: "e")
            .target = statusItem
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Days Until", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
