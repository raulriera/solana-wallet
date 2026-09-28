import RPC

/// An acknowledgment of a submitted transaction, with independently owned delivery attempts.
nonisolated struct Submission: Sendable, Equatable {
    /// The locally verified first signature identifying the submitted transaction.
    let signature: String
    /// The network to use for subsequent execution and confirmation checks.
    let network: Network

    private let broadcast: Broadcast?

    /// Creates an acknowledgment without asserting execution or finalization.
    ///
    /// - Parameters:
    ///   - signature: The transaction identifier acknowledged by the provider.
    ///   - network: The selected network used for submission.
    ///   - broadcast: The pending deliveries owned by this receipt, if any.
    init(signature: String, network: Network, broadcast: Broadcast? = nil) {
        self.signature = signature
        self.network = network
        self.broadcast = broadcast
    }

    /// Waits for all provider outcomes without delaying the initial acknowledgment.
    ///
    /// - Returns: Independent delivery results, or an empty array for a restored receipt.
    func deliveryResults() async -> [Broadcast.Attempt] { await broadcast?.results() ?? [] }

    /// Stops pending deliveries without revoking a transaction already received by a node.
    func cancelPendingDeliveries() { broadcast?.cancel() }

    /// Compares receipts by transaction identity rather than delivery progress.
    ///
    /// - Parameters:
    ///   - lhs: The first receipt to compare.
    ///   - rhs: The second receipt to compare.
    /// - Returns: Whether both receipts identify the same transaction and network.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.signature == rhs.signature && lhs.network == rhs.network
    }
}
