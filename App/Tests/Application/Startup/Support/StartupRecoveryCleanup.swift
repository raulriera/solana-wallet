import Testing
@testable import widgets

/// Completes or fails immediately while counting how often startup waited for the launch cleanup.
actor StartupRecoveryCleanup: RecoveryCleaning {
    private let failure: (any Error)?
    private(set) var completions = 0

    /// Configures the scripted outcome of every completion.
    /// - Parameter failure: The error thrown instead of completing, if any.
    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    /// Records the wait and returns or throws as scripted.
    /// - Throws: The scripted failure.
    func complete() async throws {
        completions += 1
        if let failure { throw failure }
    }
}
