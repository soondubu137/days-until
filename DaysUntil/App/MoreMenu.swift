import AppKit
import ServiceManagement

/// The popover's ••• menu: editing, and the app's settings, which apply at once like any Mac menu.
/// It's rebuilt each time it opens, so each menu bar style can show what the item would read right now.
final class MoreMenu: NSObject {
    private let store: CountdownStore
    private let state: PopoverState
    /// Opens the About panel. Set by the status item controller, which closes the popover first.
    var showAbout: () -> Void = {}

    init(store: CountdownStore, state: PopoverState) {
        self.store = store
        self.state = state
    }

    func make() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let edit = item(String(localized: "Edit Countdown…"), action: #selector(edit), key: "e")
        // An ellipsis, as Finder's Empty Trash… has, since the popover asks first.
        let delete = item(String(localized: "Delete Countdown…"), action: #selector(deleteCountdown))
        // From the New Countdown form there's nothing to edit or delete yet.
        edit.isEnabled = store.countdown != nil
        delete.isEnabled = store.countdown != nil
        menu.addItem(edit)
        menu.addItem(delete)
        menu.addItem(.separator())
        menu.addItem(submenu(String(localized: "Menu Bar"), items: styleItems()))
        if #available(macOS 26, *) {
            menu.addItem(submenu(String(localized: "Background"), items: backgroundItems()))
        }
        // A new install's form has its own checkbox, which applies once the countdown starts.
        if store.isSetUp {
            state.launchAtLogin.refresh()
            let launch = item(String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin))
            switch state.launchAtLogin.status {
            case .enabled: launch.state = .on
            case .requiresApproval: launch.state = .mixed
            default: launch.state = .off
            }
            menu.addItem(launch)
        }
        // Only while a change has failed: retrying won't fix a cause that lasts, but adding it there can.
        if state.launchAtLogin.failedRequest != nil {
            menu.addItem(item(String(localized: "Login Items Settings…"), action: #selector(openLoginItemsSettings)))
        }
        // Like Launch at Login, left to the form's checkbox until a countdown starts. The milestones are
        // fixed, so the name stays short and the tooltip names them.
        if store.isSetUp, let milestones = state.milestones {
            let notify = item(String(localized: "Notify Me"), action: #selector(toggleNotifications))
            notify.toolTip = MilestoneNotifications.summary
            notify.state = milestones.state
            menu.addItem(notify)
            // While macOS has them off, as Launch at Login offers Login Items Settings….
            if notify.state == .mixed {
                menu.addItem(item(String(localized: "Notification Settings…"), action: #selector(openNotificationSettings)))
            }
        }
        menu.addItem(.separator())
        // The version is in the standard About panel, beside Quit as in any app's menu.
        menu.addItem(item(String(localized: "About Days Until"), action: #selector(about)))
        // Under About, where every Mac app keeps Check for Updates…, which is in it with how they install.
        if let updates = state.updates {
            menu.addItem(submenu(String(localized: "Updates"), items: updateItems(updates)))
        }
        // A local action avoids the automatic Quit icon and its section-wide inset on macOS 26.
        menu.addItem(item(String(localized: "Quit Days Until"), action: #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    /// Each style with what the item would read with it now, right-aligned and secondary.
    private func styleItems() -> [NSMenuItem] {
        let font = NSFont.menuFont(ofSize: 0)
        let previewFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let rows = MenuBarStyle.allCases.map { style in (style, style.title, preview(of: style)) }
        let titleWidth = rows.map { NSAttributedString(string: $0.1, attributes: [.font: font]).size().width }.max() ?? 0
        let previewWidth = rows.map { NSAttributedString(string: $0.2, attributes: [.font: previewFont]).size().width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titleWidth + 24 + previewWidth))]

        return rows.map { style, title, preview in
            let item = self.item(title, action: #selector(pickStyle(_:)))
            item.representedObject = style.rawValue
            item.state = store.menuBarStyle == style ? .on : .off
            if !preview.isEmpty {
                let text = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
                text.append(NSAttributedString(
                    string: "\t\(preview)",
                    attributes: [.font: previewFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
                ))
                item.attributedTitle = text
            }
            return item
        }
    }

    /// What the menu bar item would read with `style` right now.
    private func preview(of style: MenuBarStyle) -> String {
        guard let countdown = store.countdown else { return "" }
        let calendar = Calendar.local
        let moment = CountdownMath.moment(of: countdown, calendar: calendar)
        switch CountdownMath.menuBarDisplay(moment: moment, style: style, now: Date(), calendar: calendar).text {
        case .remaining(let text): return text
        case .today: return String(localized: "Today")
        case .iconOnly: return ""
        }
    }

    private func backgroundItems() -> [NSMenuItem] {
        PopoverBackground.allCases.map { background in
            let title = switch background {
            case .liquidGlass: String(localized: "Liquid Glass")
            case .solid: String(localized: "Solid")
            }
            let item = item(title, action: #selector(pickBackground(_:)))
            item.representedObject = background.rawValue
            item.state = store.popoverBackground == background ? .on : .off
            return item
        }
    }

    /// When Sparkle last looked, as Time Machine's menu shows its latest backup above Back Up Now, then
    /// Check for Updates…, then the three choices.
    private func updateItems(_ updates: Updates) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let lastCheck = updates.lastCheck {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            let checked = NSMenuItem(title: String(localized: "Last checked: \(formatter.string(from: lastCheck))"), action: nil, keyEquivalent: "")
            checked.isEnabled = false
            items.append(checked)
        }
        let check = item(String(localized: "Check for Updates…"), action: #selector(checkForUpdates))
        check.isEnabled = updates.canCheckForUpdates
        items += [check, .separator()]
        items += UpdatePolicy.allCases.enumerated().map { index, policy in
            let title = switch policy {
            case .installAutomatically: String(localized: "Install Automatically")
            case .askFirst: String(localized: "Ask Before Installing")
            case .off: String(localized: "Don't Check")
            }
            let item = item(title, action: #selector(pickUpdatePolicy(_:)))
            item.tag = index
            item.state = updates.policy == policy ? .on : .off
            return item
        }
        return items
    }

    @objc private func edit() {
        state.edit()
    }

    @objc private func deleteCountdown() {
        state.confirmDelete()
    }

    @objc private func pickStyle(_ item: NSMenuItem) {
        if let style = (item.representedObject as? String).flatMap(MenuBarStyle.init) {
            store.menuBarStyle = style
        }
    }

    @objc private func pickBackground(_ item: NSMenuItem) {
        if let background = (item.representedObject as? String).flatMap(PopoverBackground.init) {
            store.popoverBackground = background
        }
    }

    @objc private func pickUpdatePolicy(_ item: NSMenuItem) {
        state.updates?.policy = UpdatePolicy.allCases[item.tag]
    }

    @objc private func checkForUpdates() {
        state.updates?.checkForUpdates()
    }

    @objc private func openLoginItemsSettings() {
        state.launchAtLogin.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        state.launchAtLogin.toggle()
    }

    @objc private func toggleNotifications() {
        state.milestones?.toggle()
    }

    @objc private func openNotificationSettings() {
        state.milestones?.openSettings()
    }

    @objc private func about() {
        showAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
