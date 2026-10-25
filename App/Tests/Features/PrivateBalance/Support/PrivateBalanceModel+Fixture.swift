@testable import RPC
@testable import widgets

extension PrivateBalanceModel {
    /// Creates a window's private balance on devnet over in-memory storage and local responses.
    /// - Parameters:
    ///   - responses: The local provider responses.
    ///   - keys: The saved private-balance keys.
    ///   - notes: The saved private notes.
    ///   - recovery: The recovery store, or `nil` for the fixture recovery.
    ///   - transactions: The shared transactions that deposits use and whose settled transactions start follow-ups.
    /// - Returns: The model.
    /// - Throws: A fixture error.
    static func fixture(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                        notes: StoredValue<PrivateBalances.Notes> = StoredValue(),
                        recovery: SecurityRecoveryStore? = nil,
                        transactions: TransactionStore = .unused) throws -> PrivateBalanceModel {
        let balances = PrivateBalances.inMemory(keys: keys, notes: notes,
                                                recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(),
                                                responses: responses)
        return PrivateBalanceModel(balances: balances, transactions: transactions, network: .devnet)
    }
}
