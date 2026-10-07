import SwiftUI

/// One quiet line about updates under the popover's content, like the launch at login one. A line that
/// asks for a decision always offers Later, so it never stays without a way to put it off.
struct UpdateFeedback: View {
    @ObservedObject var updates: Updates

    var body: some View {
        switch updates.line {
        case .available(let version):
            line("Version \(version) is available.") {
                Button("Details", action: updates.details)
                Button("Later", action: updates.later)
            }
        case .ready(let version):
            line("Version \(version) is ready.") {
                Button("Install and Relaunch", action: updates.installAndRelaunch)
                Button("Later", action: updates.later)
            }
        case .updated(let version):
            line("Updated to version \(version).") {
                Button("What's New", action: updates.whatsNew)
            }
        case nil:
            EmptyView()
        }
    }

    private func line(_ message: LocalizedStringKey, @ViewBuilder actions: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(message)
                .foregroundStyle(.secondary)
            // Apart from each other more than from the message, so two read as two.
            HStack(spacing: 12) {
                actions()
            }
            .buttonStyle(.link)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
