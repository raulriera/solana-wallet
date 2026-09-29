/// A request for one page of a wallet's DAS assets, including fungible tokens.
public struct GetAssetsByOwner: RPCRequest {
    /// The DAS method name for listing a wallet's assets.
    public static let method = "getAssetsByOwner"

    /// One page of indexed assets and optional native SOL information.
    public struct Response: Decodable, Sendable {
        /// The latest slot fully indexed by DAS, if supplied.
        public let lastIndexedSlot: UInt64?
        /// The one-based page number returned by the provider.
        public let page: Int
        /// The page size returned by the provider.
        public let limit: Int
        /// The assets on this page.
        public let items: [Asset]
        /// The native SOL balance, if requested and supplied.
        public let nativeBalance: NativeBalance?

        /// Creates a page of indexed holdings.
        ///
        /// - Parameters:
        ///   - lastIndexedSlot: The indexing watermark, or `nil` if unknown.
        ///   - page: The one-based page number.
        ///   - limit: The page size.
        ///   - items: The assets on the page.
        ///   - nativeBalance: The wallet's native SOL information, or `nil` if absent.
        public init(lastIndexedSlot: UInt64?, page: Int, limit: Int, items: [Asset], nativeBalance: NativeBalance?) {
            self.lastIndexedSlot = lastIndexedSlot
            self.page = page
            self.limit = limit
            self.items = items
            self.nativeBalance = nativeBalance
        }

        private enum CodingKeys: String, CodingKey {
            case lastIndexedSlot = "last_indexed_slot"
            case page, limit, items, nativeBalance
        }
    }

    /// The base-58 encoded wallet address to query.
    public let owner: String
    /// The one-based page number to request.
    public let page: Int
    /// The maximum number of assets to request on this page.
    public let limit: Int
    /// Whether the response should include native SOL information.
    public let includesNativeBalance: Bool

    /// Creates a request for one page of a wallet's indexed holdings.
    ///
    /// - Parameters:
    ///   - owner: The wallet address. The server validates this value.
    ///   - page: The one-based page number. The default is 1.
    ///   - limit: The page size, up to 1,000. The server validates this value.
    ///   - includesNativeBalance: Whether to include native SOL. The default is `true`.
    public init(owner: String, page: Int = 1, limit: Int = 1_000, includesNativeBalance: Bool = true) {
        self.owner = owner
        self.page = page
        self.limit = limit
        self.includesNativeBalance = includesNativeBalance
    }

    /// Encodes the DAS parameters as a named object.
    ///
    /// - Parameter encoder: The encoder that receives the parameter object.
    /// - Throws: An encoding error if a parameter can't be represented.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(owner, forKey: .owner)
        try container.encode(page, forKey: .page)
        try container.encode(limit, forKey: .limit)
        try container.encode(Options(showNativeBalance: includesNativeBalance), forKey: .options)
    }

    private enum CodingKeys: String, CodingKey {
        case owner = "ownerAddress"
        case page, limit, options
    }

    private struct Options: Encodable {
        let showFungible = true
        let showCollectionMetadata = true
        let showUnverifiedCollections = true
        let showNativeBalance: Bool
    }
}
