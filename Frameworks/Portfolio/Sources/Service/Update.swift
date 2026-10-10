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
    /// The provider's increasing state order, shared by all streams from that service instance.
    ///
    /// Replaying or forwarding an update preserves this value. It is independent of wall time
    /// and must not be compared with revisions from another provider instance.
    public let revision: UInt64
    /// The order in which this complete snapshot became available, or `nil` without a snapshot.
    ///
    /// Cached snapshots keep their revision when a later operation reports progress or fails.
    /// This lets consumers retain newer unsaved data while still presenting a subsequent error.
    /// A provider change gives cached snapshots a newer revision, so consumers replace copies that show
    /// the previous provider's logos.
    public let snapshotRevision: UInt64?

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
    ///   - revision: The provider's increasing order for this state.
    ///   - snapshotRevision: The snapshot's original order; omitted when it first appears in this update.
    public init(snapshot: Snapshot?, phase: Phase, revision: UInt64, snapshotRevision: UInt64? = nil) {
        self.snapshot = snapshot
        self.phase = phase
        self.revision = revision
        self.snapshotRevision = snapshot == nil ? nil : (snapshotRevision ?? revision)
    }
}
