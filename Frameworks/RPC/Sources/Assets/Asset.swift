public import Foundation

/// An indexed digital asset and the descriptive information supplied by DAS.
public struct Asset: Decodable, Sendable {
    /// The asset identifier, which is the mint address for a fungible token.
    public let id: String
    /// The asset's interface name, including interfaces unknown to this client.
    public let interface: String
    /// The asset's name, if metadata provides one.
    public let name: String?
    /// The asset's ticker symbol, if available.
    public let symbol: String?
    /// The provider's HTTPS CDN copy of the asset's image, if available.
    public let imageURL: URL?
    /// The complete descriptive metadata supplied by the provider.
    public let metadata: Metadata?

    /// Creates an asset from its identity and metadata.
    ///
    /// - Parameters:
    ///   - id: The asset identifier.
    ///   - interface: The DAS interface name.
    ///   - name: The asset's name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - imageURL: The provider's HTTPS CDN image, or `nil` if unavailable.
    ///   - metadata: The descriptive metadata, or `nil` if absent.
    public init(id: String, interface: String, name: String?, symbol: String?, imageURL: URL?, metadata: Metadata? = nil) {
        self.id = id
        self.interface = interface
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.metadata = metadata
    }
}
