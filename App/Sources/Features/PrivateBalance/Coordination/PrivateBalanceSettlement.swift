/// Records a private move's outcome in the account's private balance once the move settles.
nonisolated struct PrivateBalanceSettlement: TransactionSettling {
    /// The private balances of every account.
    let balances: any PrivateBalancing
    /// The prepared move, which the outcome completes.
    let transaction: PreparedPrivateTransaction

    /// Records the move's outcome in the account's notes and codes.
    ///
    /// A failure isn't reported: the next read of the indexer still finds the settled move.
    /// - Parameter confirmation: The move's settled outcome.
    func settle(_ confirmation: Confirmation) async {
        _ = try? await balances.complete(transaction, with: confirmation)
    }
}
