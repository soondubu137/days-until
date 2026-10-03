import ServiceManagement
import SwiftUI

/// One quiet line under the popover's content when launch at login didn't take: a refused request,
/// or one waiting on approval in System Settings. macOS's reason is in the tooltip.
struct LaunchAtLoginFeedback: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        if let enabling = launchAtLogin.failedRequest {
            line(enabling ? "Couldn't turn on launch at login." : "Couldn't turn off launch at login.",
                 action: "Try Again", perform: launchAtLogin.retry)
                .help(launchAtLogin.failureReason ?? "")
        } else if launchAtLogin.status == .requiresApproval {
            line("Launch at login needs approval.", action: "Open Settings…", perform: launchAtLogin.openSettings)
        }
    }

    private func line(_ message: LocalizedStringKey, action: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Text(message)
                .foregroundStyle(.secondary)
            Button(action, action: perform)
                .buttonStyle(.link)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
