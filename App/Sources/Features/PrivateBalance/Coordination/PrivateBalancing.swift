import RPC

/// Turns on, refreshes, transacts with, and deletes accounts' Solana Rings private balances.
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

    /// Builds a private-balance transaction for review, syncing the account's notes first.
    ///
    /// Reading the keys doesn't ask the person to authenticate; signing the transaction does. An account's first
    /// deposit also registers its keys. A send reads the recipient's registry record while the notes sync.
    /// - Parameters:
    ///   - request: The deposit, send, or withdrawal.
    ///   - account: The account that signs and pays.
    ///   - network: The network to run on.
    /// - Returns: The transaction's instructions and the change it makes once it succeeds.
    /// - Throws: ``PrivateBalanceError/unavailable`` on a network or with a provider without private balances,
    ///   ``PrivateBalanceError/turnedOff`` without keys, ``PrivateBalanceError/recipientUnregistered`` for a send to
    ///   an account without private balances, which a regular payment can reach instead,
    ///   ``PrivateBalanceError/insufficientBalance`` or ``PrivateBalanceError/tooManyNotes`` if the spendable notes
    ///   can't cover the amount, ``PrivateBalanceError/registeredWithOtherKeys``, a validation error for a zero
    ///   amount, `CancellationError`, or a storage, provider, or proof error.
    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction

    /// Records a prepared transaction's settled outcome in the account's notes.
    ///
    /// A succeeded deposit stays pending and a spend's notes leave at once, until the indexer reports the transaction;
    /// a failed or dropped transaction changes nothing.
    /// - Parameters:
    ///   - transaction: The transaction from ``prepare(_:from:on:)``.
    ///   - confirmation: The transaction's settled outcome on the same network.
    /// - Returns: The account's balance afterward, or why it has none.
    /// - Throws: A validation error for a confirmation from another network, `CancellationError` if ``removeAll()``
    ///   ran first, or a storage error.
    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus

    /// Deletes every account's private-balance keys and notes.
    ///
    /// An enable or refresh that is still running saves nothing afterward.
    /// - Throws: A storage or cancellation error.
    func removeAll() async throws
}
