import Observation

/// Counts an app-wide event while the app runs, such as a reset or a provider change,
/// so every window that reads ``value`` responds.
@MainActor
@Observable
final class Revision {
    /// Increases each time the event happens.
    private(set) var value = 0

    /// Records the event for every window that reads ``value``.
    func advance() {
        value += 1
    }
}
