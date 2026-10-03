import SwiftUI

/// Shared feedback for the first countdown and subsequent changes from the menu.
struct LaunchAtLoginFeedback: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        if launchAtLogin.failure != nil || launchAtLogin.guidance != nil {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text(launchAtLogin.statusTitle)
                    .font(.subheadline.weight(.semibold))
                if let failure = launchAtLogin.failure {
                    Text(failure)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if let guidance = launchAtLogin.guidance {
                    Text(guidance)
                        .font(.callout)
                }
                HStack {
                    if launchAtLogin.failure != nil {
                        Button("Try Again", action: launchAtLogin.retry)
                    }
                    Button("Open Login Items Settings…", action: launchAtLogin.openSettings)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}
