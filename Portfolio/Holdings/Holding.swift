public import Foundation
public import RPC

/// An asset held by a wallet, with optional descriptive and pricing information.
public struct Holding: Codable, Sendable, Equatable, Identifiable {
    /// An asset's identity within the snapshot's network.
    public enum Identity: Codable, Sendable, Hashable {
        /// Native SOL, distinct from wrapped SOL tokens.
        case nativeSOL
        /// A DAS asset identifier, such as a fungible token's mint address.
        case asset(String)
    }

    /// The identity of the holding within its network.
    public let id: Identity
    /// The exact amount, or `nil` if DAS doesn't supply its balance or decimals.
    public let amount: Amount?
    /// The display name, if metadata supplies one.
    public let name: String?
    /// The ticker symbol, if metadata supplies one.
    public let symbol: String?
    /// The image URL, if metadata supplies one.
    public let imageURL: URL?
    /// The provider's descriptive metadata, preserved through caching.
    public let metadata: Metadata?
    /// The provider's asset state, for portfolio viewing only.
    public let state: Asset.State?
    /// The available market valuation.
    public let valuation: Valuation?

    /// Creates a holding from its identity and available portfolio data.
    ///
    /// - Parameters:
    ///   - id: The asset identity within the snapshot's network.
    ///   - amount: The exact amount, or `nil` if unknown.
    ///   - name: The asset name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - imageURL: The image URL, or `nil` if unavailable.
    ///   - valuation: The available price information, or `nil` if unpriced.
    ///   - metadata: The descriptive metadata, or `nil` if unavailable.
    ///   - state: The reported asset state, or `nil` if unavailable.
    public init(id: Identity, amount: Amount?, name: String?, symbol: String?, imageURL: URL?, valuation: Valuation?,
                metadata: Metadata? = nil, state: Asset.State? = nil) {
        self.id = id
        self.amount = amount
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.valuation = valuation
        self.metadata = metadata
        self.state = state
    }
}
