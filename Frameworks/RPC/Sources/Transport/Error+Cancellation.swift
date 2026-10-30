import Foundation

extension Error {
    /// Whether the error reports cancellation or the current task is cancelled.
    var isCancellation: Bool {
        Task.isCancelled || self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
