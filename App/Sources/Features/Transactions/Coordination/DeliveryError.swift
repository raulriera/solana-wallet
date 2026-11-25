/// An error from sending or confirming a transaction, with the transaction's pending outcome.
nonisolated struct DeliveryError: Error, Sendable {
    let outcome: Outcome
    let cause: any Error
}
