import LocalAuthentication
import Synchronization

/// An authentication context and whether its operation was cancelled or timed out.
final class AuthenticationContext: @unchecked Sendable {
    /// Whether an operation is running, cancelled, or timed out.
    private enum Outcome {
        case running
        case cancelled
        case timedOut
    }

    let context: LAContext
    private let outcome = Mutex(Outcome.running)

    /// Creates an authentication context for one operation.
    ///
    /// - Parameters:
    ///   - context: An unused context.
    ///   - reason: The localized reason to show during authentication.
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

    /// Marks the operation as timed out and dismisses any pending authentication prompt.
    func timeOut() {
        outcome.withLock { if case .running = $0 { $0 = .timedOut } }
        context.invalidate()
    }

    /// Throws if the operation was cancelled or timed out.
    ///
    /// - Throws: `CancellationError` if cancelled, or ``KeychainStoreError/interactionNotAllowed`` if timed out.
    func checkRunning() throws {
        try outcome.withLock {
            switch $0 {
            case .running: break
            case .cancelled: throw CancellationError()
            case .timedOut: throw KeychainStoreError.interactionNotAllowed
            }
        }
    }

    /// Invalidates the context.
    func finish() { context.invalidate() }
}
