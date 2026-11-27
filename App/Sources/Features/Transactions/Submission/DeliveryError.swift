/// An error from sending a transaction, with the transaction's pending outcome.
nonisolated struct DeliveryError: Error, Sendable {
    let outcome: TransactionOutcome
}
