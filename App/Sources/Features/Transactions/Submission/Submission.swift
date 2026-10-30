import RPC

/// A signed transaction's receipt: its signature, network, and blockhash expiry.
nonisolated struct Submission: Sendable, Equatable {
    /// The transaction's first signature, which identifies it.
    let signature: String
    let network: Network
    let lastValidBlockHeight: UInt64

    /// Creates a receipt.
    ///
    /// - Parameters:
    ///   - signature: The transaction's first signature.
    ///   - network: The network that the transaction is sent on.
    ///   - lastValidBlockHeight: The last block height at which the blockhash is valid.
    init(signature: String, network: Network, lastValidBlockHeight: UInt64) {
        self.signature = signature
        self.network = network
        self.lastValidBlockHeight = lastValidBlockHeight
    }
}

nonisolated extension Submission {
    /// Creates the receipt for a transaction signed from a preparation.
    ///
    /// - Parameters:
    ///   - signature: The transaction's first signature.
    ///   - preparation: The preparation that supplies the network and blockhash expiry.
    init(signature: String, preparation: Preparation) {
        self.init(signature: signature, network: preparation.network,
                  lastValidBlockHeight: preparation.source.lastValidBlockHeight)
    }
}
