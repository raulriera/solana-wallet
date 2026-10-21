import RPC

/// Turns on, refreshes, transacts with, and deletes accounts' Solana Rings private balances and their redeem codes.
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
    /// Reading the keys doesn't ask the person to authenticate; signing with a saved account does. An account's first
    /// deposit also registers its keys. A send reads the recipient's registry record while the notes sync.
    ///
    /// A new code spends the amount and a reserve from the account's notes into a one-time account at the next unused
    /// index of its code root; the reserve pays for redeeming the code into any account. A redeem or take-back sweeps a
    /// code's one-time account into the account's private balance: the one-time account signs and pays every cost,
    /// including the registration of an unregistered account, which then also signs, and ends at zero lamports.
    /// Simulate the result with ``TransactionCoordinating/simulate(_:)``, which charges a sweep's network fee, and
    /// complete the transaction that it returns.
    /// - Parameters:
    ///   - request: The deposit, send, withdrawal, code creation, redeem, or take-back.
    ///   - account: The account whose private balance changes; it signs and pays, except for a redeem or take-back.
    ///   - network: The network to run on.
    /// - Returns: The transaction's instructions and authorities, and the change it makes once it succeeds.
    /// - Throws: ``PrivateBalanceError/codeForOtherNetwork`` for a code from another network,
    ///   ``PrivateBalanceError/unavailable`` on a network or with a provider without private balances,
    ///   ``PrivateBalanceError/turnedOff`` without keys, ``PrivateBalanceError/recipientUnregistered`` for a send to
    ///   an account without private balances, which a regular payment can reach instead,
    ///   ``PrivateBalanceError/insufficientBalance`` or ``PrivateBalanceError/tooManyNotes`` if the spendable notes
    ///   can't cover the amount, ``PrivateBalanceError/codeRedeemed``, ``PrivateBalanceError/codeNotReady``, or
    ///   ``PrivateBalanceError/codeUnderfunded`` for a code that can't be swept,
    ///   ``PrivateBalanceError/registeredWithOtherKeys``, a validation error for a zero amount, `CancellationError`,
    ///   or a storage, provider, or proof error.
    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction

    /// Records a prepared transaction's settled outcome in the account's notes and codes.
    ///
    /// A succeeded deposit or sweep stays pending and a spend's notes leave at once, until the indexer reports the
    /// transaction; a new code joins the account's codes, and a code taken back leaves them. A failed or dropped
    /// transaction changes no balance; a failed or dropped code's index is never used again.
    /// - Parameters:
    ///   - transaction: The transaction from ``prepare(_:from:on:)``.
    ///   - confirmation: The transaction's settled outcome on the same network.
    /// - Returns: The account's balance afterward, or why it has none.
    /// - Throws: A validation error for a confirmation from another network, `CancellationError` if ``removeAll()``
    ///   ran first, or a storage error.
    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus

    /// Lists the account's redeem codes that the indexer doesn't show as spent, dropping codes that were redeemed or
    /// taken back.
    ///
    /// Without a record of the account's codes, such as after a restore, the indexer is scanned for them first. A
    /// code whose funding the indexer doesn't report yet stays listed, and a prepared code whose funding landed without
    /// being recorded, such as when the app quit first, joins the list.
    /// - Parameters:
    ///   - account: The account that created the codes.
    ///   - network: The network that holds them.
    /// - Returns: The outstanding codes, by index.
    /// - Throws: ``PrivateBalanceError/unavailable`` on a network or with a provider without private balances,
    ///   ``PrivateBalanceError/turnedOff`` without keys, `CancellationError` if cancelled or if ``removeAll()`` ran
    ///   first, or a storage or provider error.
    func outstandingCodes(of account: Account, on network: Network) async throws -> [OutstandingRedeemCode]

    /// Deletes every account's private-balance keys, notes, and redeem codes.
    ///
    /// An enable or refresh that is still running saves nothing afterward.
    /// - Throws: A storage or cancellation error.
    func removeAll() async throws
}
