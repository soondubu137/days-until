import Foundation

extension UserDefaults {
    /// Clears a test's defaults domain and deletes its plist. `removePersistentDomain` alone
    /// leaves the file behind, empty, in the app's container, one more for every run.
    static func removeTestSuite(_ suite: String) {
        standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: .libraryDirectory.appending(path: "Preferences/\(suite).plist"))
    }
}
