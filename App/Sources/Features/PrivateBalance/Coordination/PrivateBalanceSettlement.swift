import RPC

/// Records a settled private move's outcome in the account's private balance.
nonisolated struct PrivateBalanceSettlement: TransactionSettling {
    let balances: any PrivateBalancing
    let transaction: PreparedPrivateTransaction

    func settle(_ outcome: TransactionOutcome) async {
        _ = try? await balances.complete(transaction, with: outcome)
    }
}
