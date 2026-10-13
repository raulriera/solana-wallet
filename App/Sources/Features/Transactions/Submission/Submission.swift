import RPC

/// A signed transaction's identifier, network, and blockhash expiry, without asserting delivery or execution.
nonisolated struct Submission: Sendable, Equatable {
    /// The locally verified first signature identifying the signed transaction.
    let signature: String
    /// The network to use for subsequent execution and confirmation checks.
    let network: Network
    /// The last block height at which the transaction's blockhash is valid.
    ///
    /// For an imported transaction, this is an upper bound read when it was prepared.
    let lastValidBlockHeight: UInt64

    /// Creates a receipt without asserting delivery, execution, or finalization.
    ///
    /// - Parameters:
    ///   - signature: The transaction's first signature.
    ///   - network: The selected network used for submission.
    ///   - lastValidBlockHeight: The last block height at which the blockhash is valid.
    init(signature: String, network: Network, lastValidBlockHeight: UInt64) {
        self.signature = signature
        self.network = network
        self.lastValidBlockHeight = lastValidBlockHeight
    }
}

nonisolated extension Submission {
    /// Creates the receipt for a signed transaction from the review it was signed from.
    ///
    /// - Parameters:
    ///   - signature: The transaction's first signature.
    ///   - preparation: The review that supplies the network and blockhash expiry.
    init(signature: String, preparation: Preparation) {
        self.init(signature: signature, network: preparation.network,
                  lastValidBlockHeight: preparation.source.lastValidBlockHeight)
    }
}
