import Testing
@testable import widgets

/// Completes or fails immediately while counting how often startup waited for the launch cleanup.
actor StartupRecoveryCleanup: RecoveryCleaning {
    private let error: (any Error)?
    private(set) var completions = 0

    /// Configures the scripted outcome of every completion.
    /// - Parameter error: The error thrown instead of completing, if any.
    init(error: (any Error)? = nil) {
        self.error = error
    }

    /// Records the wait and returns or throws as scripted.
    /// - Throws: The scripted failure.
    func complete() async throws {
        completions += 1
        if let error { throw error }
    }
}
