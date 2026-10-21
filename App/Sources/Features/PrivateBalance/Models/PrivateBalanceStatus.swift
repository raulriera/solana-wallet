import Privacy

/// What an account's private balance shows on a network after a refresh.
nonisolated enum PrivateBalanceStatus: Equatable, Sendable {
    /// Private balances aren't turned on for the account: this device has no keys for it, and the selected provider
    /// reads them.
    case off
    /// The network has no private balances, or the selected provider doesn't read them.
    case unavailable
    /// The account has keys, but hasn't registered them on the network.
    case unregistered
    /// The account's unspent private SOL, in lamports: the notes that it can spend now, and the recorded deposits and
    /// changes that the indexer hasn't reported yet.
    case balance(available: UInt64, pending: UInt64)

    /// Shows an account's synced notes as its balance.
    /// - Parameter state: The account's notes and pending amounts.
    /// - Returns: The notes that the account can spend now, and its pending amounts.
    static func balance(of state: NoteSyncState) -> PrivateBalanceStatus {
        .balance(available: state.lamports - state.pendingLamports, pending: state.pendingLamports)
    }
}
