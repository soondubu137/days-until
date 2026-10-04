import SwiftUI

/// Asked in the popover, in the countdown's place, before it's deleted. Not an alert, which from a
/// popover would be a window of its own, but laid out like one on macOS 26: the countdown's icon,
/// the question with its name, its day, and two equal buttons. As in macOS's alerts, Delete is
/// marked in red and isn't the default button, so Return can't delete. Esc cancels.
struct DeleteConfirmation: View {
    let countdown: Countdown
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CountdownIconView(icon: countdown.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: Radius.largeTile, style: .continuous))
                .accessibilityHidden(true)
            Text("Delete “\(countdown.name)”?")
                .font(.headline)
                .padding(.top, 14)
            Text(CountdownView.longDate(of: countdown))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)
                // The system's red-tinted destructive button is private to alerts, so the system
                // button with its title in red.
                Button(role: .destructive, action: onDelete) {
                    Text("Delete").foregroundStyle(Color.danger).frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
