@testable import RPC
@testable import widgets

extension PrivateBalanceStore {
    static func fixture(_ responses: HTTPResponses, keys: StoredValue<PrivateBalances.Keys> = StoredValue(),
                        notes: StoredValue<PrivateBalances.Notes> = StoredValue(),
                        recovery: SecurityRecoveryStore? = nil,
                        transactions: TransactionStore = .unused, rpcStore: RPCStore = .inMemory(),
                        pollInterval: Duration = .seconds(30),
                        followUpInterval: Duration = .seconds(3)) throws -> PrivateBalanceStore {
        let balances = PrivateBalances.inMemory(keys: keys, notes: notes,
                                                recovery: try recovery ?? PrivateBalanceFixtures.recoveryStore(),
                                                responses: responses)
        return PrivateBalanceStore(balances: balances, transactions: transactions, rpcStore: rpcStore,
                                   pollInterval: pollInterval, followUpInterval: followUpInterval)
    }
}
