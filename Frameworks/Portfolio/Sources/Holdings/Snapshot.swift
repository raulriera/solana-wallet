public import RPC

/// A complete balance read for one wallet and network.
public struct Snapshot: Codable, Sendable, Equatable {
    /// The wallet whose holdings were retrieved.
    public let owner: String
    /// The network to which these holdings belong.
    public let network: Network
    /// Native SOL followed by the wallet's listed tokens.
    public internal(set) var holdings: [Holding]

    /// Creates a portfolio snapshot for a wallet and network.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - network: The Solana network.
    ///   - holdings: Native SOL followed by the listed tokens.
    public init(owner: String, network: Network, holdings: [Holding]) {
        self.owner = owner
        self.network = network
        self.holdings = holdings
    }
}
