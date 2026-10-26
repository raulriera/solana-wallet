import RPC

/// A transaction that the person reviews and approves, such as a payment: how it's prepared and simulated, what its
/// review shows, and the errors that its alerts explain.
///
/// ``TransactionReviewModel`` prepares a proposal once per review and simulates it again while the review shows, so the
/// review never expires; a cancelled authentication uses up a simulation, so the model simulates the same preparation
/// again.
@MainActor
protocol TransactionProposal {
    /// What the proposal prepares once per review, such as a proof, which each simulation uses.
    associatedtype Preparation = Void
    /// What the review shows about each simulation, such as its fees.
    associatedtype Review: Equatable & Sendable
    /// The errors that the review's alerts explain.
    associatedtype Error: TransactionReviewError

    /// How often an open review simulates the transaction again, well before its blockhash expires.
    var refreshInterval: Duration { get }

    /// Prepares what every simulation of this review uses.
    /// - Parameters:
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    /// - Returns: The preparation.
    /// - Throws: ``Error`` when the transaction can't be prepared, or the underlying error.
    func prepare(from account: Account, on network: Network) async throws -> Preparation

    /// Simulates the transaction and reads what its review shows.
    /// - Parameters:
    ///   - preparation: What the review prepared.
    ///   - coordinator: The network's transaction coordinator, which simulates the transaction.
    ///   - account: The account that signs and pays.
    /// - Returns: The simulation to approve, its review, and what its record says.
    /// - Throws: ``Error`` when the simulation shows the transaction can't be sent, or the simulation's error.
    func simulate(_ preparation: Preparation, with coordinator: any TransactionCoordinating, from account: Account)
        async throws -> ProposedTransaction<Review>
}

extension TransactionProposal where Preparation == Void {
    /// Prepares nothing, for a transaction that each simulation builds in full.
    /// - Parameters:
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    func prepare(from account: Account, on network: Network) async throws {}
}
