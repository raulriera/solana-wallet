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
    public init(id: String, interface: String, name: String?, symbol: String?, imageURL: URL?, balance: UInt64?, decimals: UInt8?, price: Price?) {
        self.id = id
        self.interface = interface
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.balance = balance
        self.decimals = decimals
        self.price = price
    }

    /// Decodes an asset without requiring metadata or market prices.
    ///
    /// A non-string image link is treated as missing, allowing an image file
    /// to supply the URL while preserving the asset's other metadata.
    ///
    /// - Parameter decoder: The decoder containing the DAS asset.
    /// - Throws: A decoding error if an identity or supplied balance is malformed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        interface = try container.decode(String.self, forKey: .interface)
        let content = try container.decodeIfPresent(Content.self, forKey: .content)
        let token = try container.decodeIfPresent(Token.self, forKey: .token)
        name = content?.metadata?.name
        symbol = token?.symbol ?? content?.metadata?.symbol
        let image = content?.links?.image
            ?? content?.files?.first(where: { $0.mime?.hasPrefix("image/") == true })?.uri
        imageURL = image.flatMap(URL.init(string:))
        balance = token?.balance
        decimals = token?.decimals
        price = token?.price
    }

    private enum CodingKeys: String, CodingKey {
        case id, interface, content
        case token = "token_info"
    }

    private struct Content: Decodable {
        let metadata: Metadata?
        let links: Links?
        let files: [File]?
    }

    private struct Metadata: Decodable {
        let name: String?
        let symbol: String?
    }

    private struct Links: Decodable {
        let image: String?

        /// Decodes an image link while treating non-string values as unavailable.
        ///
        /// - Parameter decoder: The decoder containing the link metadata.
        /// - Throws: A decoding error if the links container isn't an object.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            image = try? container.decodeIfPresent(String.self, forKey: .image)
        }

        private enum CodingKeys: String, CodingKey {
            case image
        }
    }

    private struct File: Decodable {
        let uri: String?
        let mime: String?
    }

    private struct Token: Decodable {
        let balance: UInt64?
        let decimals: UInt8?
        let symbol: String?
        let price: Price?

        private enum CodingKeys: String, CodingKey {
            case balance, decimals, symbol
            case price = "price_info"
        }
    }
}
