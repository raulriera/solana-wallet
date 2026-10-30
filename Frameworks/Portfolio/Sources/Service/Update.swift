/// A portfolio's state during one refresh cycle.
public struct Update: Sendable {
    /// The progress or outcome of the refresh.
    public enum Phase: Sendable {
        case refreshing
        /// The refresh completed and was saved.
        case ready
        case failed(any Error)
    }

    /// The latest complete snapshot, or `nil` if there's none yet.
    public let snapshot: Snapshot?
    public let phase: Phase
    /// The state's position in the provider's increasing order across all its streams.
    public let revision: UInt64
    /// The revision at which the snapshot became available, or `nil` without a snapshot.
    public let snapshotRevision: UInt64?

    /// The snapshot's holdings, or an empty array without a snapshot.
    public var holdings: [Holding] { snapshot?.holdings ?? [] }

    public var isRefreshing: Bool {
        if case .refreshing = phase { return true }
        return false
    }

    public var error: (any Error)? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    /// Creates an update.
    ///
    /// - Parameters:
    ///   - snapshot: The latest complete snapshot, or `nil` if none exists.
    ///   - phase: The refresh's phase.
    ///   - revision: The state's position in the provider's increasing order.
    ///   - snapshotRevision: The revision at which the snapshot became available, or `nil` to use `revision`.
    public init(snapshot: Snapshot?, phase: Phase, revision: UInt64, snapshotRevision: UInt64? = nil) {
        self.snapshot = snapshot
        self.phase = phase
        self.revision = revision
        self.snapshotRevision = snapshot == nil ? nil : (snapshotRevision ?? revision)
    }
}
