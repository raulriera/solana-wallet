import RPC
@testable import widgets

extension PrivateBalanceModel {
    /// Creates a window's private balance on devnet over in-memory storage and local responses.
    /// - Parameters:
    ///   - responses: The local provider responses.
    ///   - keys: The saved private-balance keys.
    ///   - recovery: The recovery store, or `nil` for the fixture recovery.
    /// - Returns: The model.
    /// - Throws: A fixture error.
    static func fixture(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                        recovery: SecurityRecoveryStore? = nil) throws -> PrivateBalanceModel {
        let balances = PrivateBalances.inMemory(keys: keys, notes: StoredValue(),
                                                recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(),
                                                responses: responses)
        return PrivateBalanceModel(balances: balances, network: .devnet)
    }
}
