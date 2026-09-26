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
    /// Malformed display metadata is treated as unavailable for that field.
    /// Identity, balances, decimal precision, and supplied prices remain strictly decoded.
    ///
    /// - Parameter decoder: The decoder containing the DAS asset.
    /// - Throws: A decoding error if identity, balance, precision, or price data is malformed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        interface = try container.decode(String.self, forKey: .interface)
        let content = try? container.decodeIfPresent(Content.self, forKey: .content)
        let token = try container.decodeIfPresent(Token.self, forKey: .token)
        name = content?.name
        symbol = token?.symbol ?? content?.symbol
        imageURL = content?.imageURL
        balance = token?.balance
        decimals = token?.decimals
        price = token?.price
    }

    private enum CodingKeys: String, CodingKey {
        case id, interface, content
        case token = "token_info"
    }

    private struct Content: Decodable {
        let name: String?
        let symbol: String?
        let imageURL: URL?

        /// Decodes display fields independently and selects an available image.
        ///
        /// - Parameter decoder: The decoder containing the asset's content.
        /// - Throws: A decoding error if the content isn't an object or a file entry can't be consumed.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let metadata = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .metadata)
            name = try? metadata?.decode(String.self, forKey: .name)
            symbol = try? metadata?.decode(String.self, forKey: .symbol)

            let links = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .links)
            let image = try? links?.decode(String.self, forKey: .image)
            var imageURL = image.flatMap(URL.init(string:))
            if imageURL == nil, var files = try? container.nestedUnkeyedContainer(forKey: .files) {
                while imageURL == nil, !files.isAtEnd {
                    let fileDecoder = try files.superDecoder()
                    guard let file = try? fileDecoder.container(keyedBy: CodingKeys.self),
                          let mime = try? file.decode(String.self, forKey: .mime), mime.hasPrefix("image/"),
                          let uri = try? file.decode(String.self, forKey: .uri) else { continue }
                    imageURL = URL(string: uri)
                }
            }
            self.imageURL = imageURL
        }

        private enum CodingKeys: String, CodingKey {
            case metadata, name, symbol, links, image, files, uri, mime
        }
    }

    private struct Token: Decodable {
        let balance: UInt64?
        let decimals: UInt8?
        let symbol: String?
        let price: Price?

        /// Decodes exact token values while allowing an unavailable display symbol.
        ///
        /// - Parameter decoder: The decoder containing the token's balance and valuation.
        /// - Throws: A decoding error if supplied balance, precision, or price data is malformed.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            balance = try container.decodeIfPresent(UInt64.self, forKey: .balance)
            decimals = try container.decodeIfPresent(UInt8.self, forKey: .decimals)
            symbol = try? container.decodeIfPresent(String.self, forKey: .symbol)
            price = try container.decodeIfPresent(Price.self, forKey: .price)
        }

        private enum CodingKeys: String, CodingKey {
            case balance, decimals, symbol
            case price = "price_info"
        }
    }
}
