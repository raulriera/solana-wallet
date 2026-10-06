import Observation

/// Counts app resets while the app runs, so every window returns to onboarding.
@MainActor
@Observable
final class AppResetRevision {
    /// Increases each time the app resets.
    private(set) var value = 0

    /// Records a reset for every window that reads ``value``.
    func advance() {
        value += 1
    }
}
