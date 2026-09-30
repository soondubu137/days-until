import AppKit
import SwiftUI

@main
struct HomeTimerApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set a date to start counting down.")
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit Home Timer") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 260, alignment: .leading)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "house")
                Text("Set date")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
