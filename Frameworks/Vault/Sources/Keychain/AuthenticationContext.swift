import LocalAuthentication
import Synchronization

/// Owns one authentication context and its cancellation state.
///
/// Safety: configure the context before sharing it, use it on one Keychain
/// queue, and only call `invalidate()` concurrently to stop authentication, as
/// supported by LocalAuthentication. Cancellation state is protected by a mutex.
/// Remove this unchecked conformance when the SDK supplies a Sendable context.
final class AuthenticationContext: @unchecked Sendable {
    let context: LAContext
    private let cancelled = Mutex(false)

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
        cancelled.withLock { $0 = true }
        context.invalidate()
    }

    /// Rejects work after cancellation, including work waiting on the queue.
    /// - Throws: `CancellationError` if this operation was canceled.
    func checkCancellation() throws {
        if cancelled.withLock({ $0 }) { throw CancellationError() }
    }

    /// Invalidates the context after use so its authentication can't be reused.
    func finish() { context.invalidate() }
}
