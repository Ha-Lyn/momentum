import Foundation

/// Runs `body` with an isolated `UserDefaults` suite and removes it afterwards.
func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suiteName = "momentum.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Could not create UserDefaults suite \(suiteName)")
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    try body(defaults)
}
