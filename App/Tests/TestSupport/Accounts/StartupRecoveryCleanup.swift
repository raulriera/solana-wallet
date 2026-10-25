import Testing
@testable import widgets

/// Completes or fails as scripted, optionally after a suspension, while counting how often a store waited for the
/// launch cleanup.
actor StartupRecoveryCleanup {
    private let error: (any Error)?
    private let gate: Suspension?
    private(set) var completions = 0

    /// Configures the scripted outcome of every completion.
    /// - Parameters:
    ///   - error: The error thrown instead of completing, if any.
    ///   - gate: An optional suspension before the outcome, for cancellation and overlap checks.
    init(error: (any Error)? = nil, gate: Suspension? = nil) {
        self.error = error
        self.gate = gate
    }

    /// Records the wait, suspends when a gate is set, and returns or throws as scripted.
    /// - Throws: The scripted failure.
    func complete() async throws {
        completions += 1
        await gate?.suspend()
        if let error { throw error }
    }
}

/// The conformance sits in an extension so the compiler doesn't infer isolation for the actor from the protocol, which
/// fails some builds with a misleading "'nonisolated' modifier cannot be applied" error on this actor.
extension StartupRecoveryCleanup: RecoveryCleaning {}
