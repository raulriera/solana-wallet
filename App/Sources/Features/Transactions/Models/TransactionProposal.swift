import RPC

/// A transaction that the person reviews and approves, such as a payment.
@MainActor
protocol TransactionProposal: SendableMetatype {
    /// What the proposal prepares once per transaction for each of its simulations to use.
    associatedtype Preparation = Void
    /// What the review shows about each simulation.
    associatedtype Review: Equatable & Sendable
    /// The errors that the review presents.
    associatedtype Error: TransactionReviewError

    /// How often an open review simulates the transaction again.
    var refreshInterval: Duration { get }

    /// Prepares what every simulation of the next transaction uses.
    ///
    /// - Parameters:
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    /// - Returns: The preparation.
    /// - Throws: ``Error`` when the transaction can't be prepared, or the underlying error.
    func prepare(from account: Account, on network: Network) async throws -> Preparation

    /// Simulates the transaction and reads what its review shows.
    ///
    /// - Parameters:
    ///   - preparation: What the review prepared.
    ///   - coordinator: The network's transaction coordinator.
    ///   - account: The account that signs and pays.
    /// - Returns: The simulation to approve, its review, and what its record says.
    /// - Throws: ``Error`` when the transaction can't be sent, or the simulation's error.
    func simulate(_ preparation: Preparation, with coordinator: any TransactionCoordinating, from account: Account)
        async throws -> ProposedTransaction<Review>
}

extension TransactionProposal where Preparation == Void {
    func prepare(from account: Account, on network: Network) async throws {}
}
