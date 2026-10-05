import Observation

/// Counts the provider keys saved while the app runs, so every window can retry with the newest key.
@MainActor
@Observable
final class ProviderKeyRevision {
    /// Increases each time a key is saved.
    private(set) var value = 0

    /// Records a saved key for every window that reads ``value``.
    func advance() {
        value += 1
    }
}
