import Foundation

extension Error {
    /// Whether the failure means cancellation, because the current task is cancelled or the error reports it.
    ///
    /// URL loading reports a cancelled request as `URLError.cancelled` rather than `CancellationError`.
    var isCancellation: Bool {
        Task.isCancelled || self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
