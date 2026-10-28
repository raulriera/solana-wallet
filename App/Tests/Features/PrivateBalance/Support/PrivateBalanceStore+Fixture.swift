@testable import RPC
@testable import widgets

extension PrivateBalanceStore {
    /// Creates the shared private balances over in-memory storage and local responses.
    /// - Parameters:
    ///   - responses: The local provider responses.
    ///   - keys: The saved private-balance keys.
    ///   - notes: The saved private notes.
    ///   - recovery: The recovery store, or `nil` for the fixture recovery.
    ///   - transactions: The shared transactions that deposits use and whose settled transactions start follow-ups.
    ///   - providers: The provider settings, whose new connections read every observed balance again.
    ///   - pollInterval: The time between polls.
    ///   - followUpInterval: The time between polls that follow up on pending SOL.
    /// - Returns: The store, before any read.
    /// - Throws: A fixture error.
    static func fixture(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                        notes: StoredValue<PrivateBalances.Notes> = StoredValue(),
                        recovery: SecurityRecoveryStore? = nil,
                        transactions: TransactionStore = .unused, providers: ProviderStore = .inMemory(),
                        pollInterval: Duration = .seconds(30),
                        followUpInterval: Duration = .seconds(3)) throws -> PrivateBalanceStore {
        let balances = PrivateBalances.inMemory(keys: keys, notes: notes,
                                                recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(),
                                                responses: responses)
        return PrivateBalanceStore(balances: balances, transactions: transactions, providers: providers,
                                   pollInterval: pollInterval, followUpInterval: followUpInterval)
    }
}
