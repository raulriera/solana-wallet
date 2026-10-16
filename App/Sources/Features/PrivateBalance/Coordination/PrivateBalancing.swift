import RPC

/// Turns on, refreshes, and deletes accounts' Solana Rings private balances.
nonisolated protocol PrivateBalancing: Sendable {
    /// Derives an account's private-balance keys from its recovery and keeps them on this device.
    ///
    /// An account whose path has no private-balance keys is rejected before the person is asked to authenticate.
    /// Reading the recovery asks the person to authenticate. On a network with private balances, keys that the
    /// account registered from another app are rejected before anything is saved.
    /// - Parameters:
    ///   - account: The account whose keys to keep.
    ///   - network: The network whose registration to check.
    /// - Throws: ``PrivateBalanceError/unsupportedAccount`` for an account without private-balance keys,
    ///   ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys, `CancellationError`
    ///   if cancelled or if ``removeAll()`` ran first, or a storage, derivation, or provider error.
    func enable(_ account: Account, on network: Network) async throws

    /// Reads an account's new and spent private notes on a network and returns its balance.
    /// - Parameters:
    ///   - account: The account whose balance to refresh.
    ///   - network: The network to read.
    /// - Returns: The account's balance, or why it has none.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys`` if the account registered other keys,
    ///   `CancellationError` if cancelled or if ``removeAll()`` ran first, or a storage or provider error; an error
    ///   never reads as a balance.
    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus

    /// Deletes every account's private-balance keys and notes.
    ///
    /// An enable or refresh that is still running saves nothing afterward.
    /// - Throws: A storage or cancellation error.
    func removeAll() async throws
}
