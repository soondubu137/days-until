import Foundation

/// Defaults that live only in memory, for tests. A real suite leaves a plist in the app's container
/// every run, even emptied and deleted: cfprefsd writes it back after the test host quits.
/// Overrides everything `CountdownStore` calls, so the suite underneath is never written.
final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: "DaysUntilTests.Memory")!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
