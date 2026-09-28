import RPC

/// A provider's acknowledgment of a submitted transaction, without execution confirmation.
nonisolated struct Submission: Sendable, Equatable {
    /// The locally verified first signature identifying the submitted transaction.
    let signature: String
    /// The network to use for subsequent execution and confirmation checks.
    let network: Network

    /// Creates an acknowledgment without asserting execution or finalization.
    ///
    /// - Parameters:
    ///   - signature: The transaction identifier acknowledged by the provider.
    ///   - network: The selected network used for submission.
    init(signature: String, network: Network) {
        self.signature = signature
        self.network = network
    }
}
