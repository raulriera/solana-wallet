/// A complete presentation state emitted during one portfolio refresh cycle.
public struct Update: Sendable {
    /// The progress or outcome of the refresh.
    public enum Phase: Sendable {
        /// Existing data is available while a refresh is running.
        case refreshing
        /// A fresh cached snapshot is available, or a requested refresh completed and was saved.
        case ready
        /// Retrieval or persistence failed, retaining the latest complete snapshot.
        case failed(any Error)
    }

    /// The most recent complete snapshot, or `nil` before the first successful retrieval.
    public let snapshot: Snapshot?
    /// The refresh's current phase.
    public let phase: Phase

    /// The available holdings, or an empty array when no snapshot exists.
    public var holdings: [Holding] { snapshot?.holdings ?? [] }

    /// A Boolean value that indicates whether the service is refreshing the portfolio.
    public var isRefreshing: Bool {
        if case .refreshing = phase { return true }
        return false
    }

    /// The refresh error, if the cycle failed.
    public var error: (any Error)? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    /// Creates an update containing both the available data and refresh status.
    ///
    /// - Parameters:
    ///   - snapshot: The complete snapshot to retain, or `nil` if none exists.
    ///   - phase: The refresh's progress or outcome.
    public init(snapshot: Snapshot?, phase: Phase) {
        self.snapshot = snapshot
        self.phase = phase
    }
}
