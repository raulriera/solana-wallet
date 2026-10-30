import RPC

/// Turns on, refreshes, transacts with, and deletes accounts' private balances and redeem codes.
nonisolated protocol PrivateBalancing: Sendable {
    /// Derives an account's private-balance keys from its recovery and keeps them on this device.
    ///
    /// - Parameters:
    ///   - account: The account whose keys to keep.
    ///   - network: The network whose registration to check.
    /// - Throws: ``PrivateBalanceError/unsupportedAccount``, ``PrivateBalanceError/registeredWithOtherKeys``, or a
    ///   storage, derivation, provider, or cancellation error.
    func enable(_ account: Account, on network: Network) async throws

    /// Reads an account's new and spent private notes on a network and returns its balance.
    ///
    /// - Parameters:
    ///   - account: The account whose balance to refresh.
    ///   - network: The network to read.
    /// - Returns: The account's balance, or why it has none.
    /// - Throws: ``PrivateBalanceError/registeredWithOtherKeys``, or a storage, provider, or cancellation error.
    func refresh(_ account: Account, on network: Network) async throws -> PrivateBalanceStatus

    /// Returns the balance that an account's saved notes hold on a network, without reading the network.
    ///
    /// - Parameters:
    ///   - account: The account whose saved balance to read.
    ///   - network: The network of the saved notes.
    /// - Returns: The saved balance, or `nil` without keys or saved notes.
    /// - Throws: A storage or cancellation error.
    func savedStatus(of account: Account, on network: Network) async throws -> PrivateBalanceStatus?

    /// Builds a private-balance transaction for review, syncing the account's notes first.
    ///
    /// - Parameters:
    ///   - request: The deposit, send, withdrawal, code creation, redeem, or take-back.
    ///   - account: The account whose private balance changes.
    ///   - network: The network to run on.
    /// - Returns: The transaction's instructions and authorities, and the change it makes once it succeeds.
    /// - Throws: A ``PrivateBalanceError`` when the transaction can't be prepared, or a validation, storage,
    ///   provider, proof, or cancellation error.
    func prepare(_ request: PrivateTransactionRequest, from account: Account, on network: Network) async throws
        -> PreparedPrivateTransaction

    /// Records a prepared transaction's settled outcome in the account's notes and codes.
    ///
    /// - Parameters:
    ///   - transaction: The prepared transaction.
    ///   - confirmation: The transaction's settled outcome on the same network.
    /// - Returns: The account's balance afterward, or why it has none.
    /// - Throws: A validation error for a confirmation from another network, or a storage or cancellation error.
    func complete(_ transaction: PreparedPrivateTransaction, with confirmation: Confirmation) async throws
        -> PrivateBalanceStatus

    /// Lists the account's redeem codes that the indexer doesn't show as spent.
    ///
    /// - Parameters:
    ///   - account: The account that created the codes.
    ///   - network: The network that holds them.
    /// - Returns: The outstanding codes, by index.
    /// - Throws: ``PrivateBalanceError/unavailable``, ``PrivateBalanceError/turnedOff``, or a storage, provider, or
    ///   cancellation error.
    func outstandingCodes(of account: Account, on network: Network) async throws -> [OutstandingRedeemCode]

    /// Deletes every account's private-balance keys, notes, and redeem codes.
    ///
    /// - Throws: A storage or cancellation error.
    func removeAll() async throws
}
