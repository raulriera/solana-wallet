import LocalAuthentication
import Synchronization

/// Owns one authentication context and whether its operation was cancelled or timed out.
///
/// Safety: configure the context before sharing it, use it on one Keychain
/// queue, and only call `invalidate()` concurrently to stop authentication, as
/// supported by LocalAuthentication. The outcome is protected by a mutex.
/// Remove this unchecked conformance when the SDK supplies a Sendable context.
final class AuthenticationContext: @unchecked Sendable {
    /// Why an operation stops before it finishes.
    private enum Outcome {
        /// The operation is still allowed to run.
        case running
        /// The user or the calling task cancelled the operation.
        case cancelled
        /// Authentication didn't finish within the time bound.
        case timedOut
    }

    let context: LAContext
    private let outcome = Mutex(Outcome.running)

    /// Configures a fresh context before the Keychain operation starts.
    ///
    /// - Parameters:
    ///   - context: An unused context owned exclusively by this operation.
    ///   - reason: The localized authentication explanation.
    init(context: LAContext, reason: String) {
        self.context = context
        context.localizedReason = reason
        context.touchIDAuthenticationAllowableReuseDuration = 0
    }

    /// Cancels the operation and dismisses any pending authentication prompt.
    func cancel() {
        outcome.withLock { if case .running = $0 { $0 = .cancelled } }
        context.invalidate()
    }

    /// Stops the operation at its time bound and dismisses any pending authentication prompt.
    func timeOut() {
        outcome.withLock { if case .running = $0 { $0 = .timedOut } }
        context.invalidate()
    }

    /// Rejects work after cancellation or a timeout, including work waiting on the queue.
    /// - Throws: `CancellationError` if the operation was cancelled, or ``KeychainStoreError/interactionNotAllowed``
    ///   if authentication didn't finish within the time bound.
    func checkRunning() throws {
        try outcome.withLock {
            switch $0 {
            case .running: break
            case .cancelled: throw CancellationError()
            case .timedOut: throw KeychainStoreError.interactionNotAllowed
            }
        }
    }

    /// Invalidates the context after use so its authentication can't be reused.
    func finish() { context.invalidate() }
}
