public import Foundation

/// An indexed digital asset and the portfolio information supplied by DAS.
public struct Asset: Decodable, Sendable {
    /// The asset identifier, which is the mint address for a fungible token.
    public let id: String
    /// The asset's interface name, including interfaces unknown to this client.
    public let interface: String
    /// The asset's name, if metadata provides one.
    public let name: String?
    /// The asset's ticker symbol, if available.
    public let symbol: String?
    /// The asset's image URL, if available.
    public let imageURL: URL?
    /// The complete descriptive metadata supplied by the provider.
    public let metadata: Metadata?
    /// The reported asset state, for portfolio viewing only.
    public let state: State?
    /// The owner's balance in raw token units, if supplied.
    public let balance: UInt64?
    /// The token's number of decimal places, if supplied.
    public let decimals: UInt8?
    /// The available price information for this holding.
    public let price: Price?

    /// Creates an asset from its identity, metadata, balance, and price.
    ///
    /// - Parameters:
    ///   - id: The asset identifier.
    ///   - interface: The DAS interface name.
    ///   - name: The asset's name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - imageURL: The image URL, or `nil` if unavailable.
    ///   - balance: The raw token units held, or `nil` if unknown.
    ///   - decimals: The decimal places, or `nil` if unknown.
    ///   - price: The available valuation, or `nil` if unpriced.
    ///   - metadata: The descriptive metadata, or `nil` if absent.
    ///   - state: The reported asset state, or `nil` if absent.
    public init(id: String, interface: String, name: String?, symbol: String?, imageURL: URL?,
                balance: UInt64?, decimals: UInt8?, price: Price?, metadata: Metadata? = nil, state: State? = nil) {
        self.id = id
        self.interface = interface
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.balance = balance
        self.decimals = decimals
        self.price = price
        self.metadata = metadata
        self.state = state
    }
}
