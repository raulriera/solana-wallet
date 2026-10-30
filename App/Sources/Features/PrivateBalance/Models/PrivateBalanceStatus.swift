import Privacy

/// The state of an account's private balance on a network.
nonisolated enum PrivateBalanceStatus: Equatable, Sendable {
    /// This device has no keys for the account, where `isRegistered` is whether the registry holds the account.
    case off(isRegistered: Bool)
    /// The network has no private balances, or the selected provider doesn't read them.
    case unavailable
    /// The account has keys, but hasn't registered them on the network.
    case unregistered
    /// The account's spendable and pending private SOL, in lamports.
    case balance(available: UInt64, pending: UInt64)

    /// Returns the balance that an account's synced notes hold.
    ///
    /// - Parameter state: The account's notes.
    /// - Returns: The available and pending balance.
    static func balance(of state: NoteSyncState) -> PrivateBalanceStatus {
        .balance(available: state.lamports - state.pendingLamports, pending: state.pendingLamports)
    }
}
