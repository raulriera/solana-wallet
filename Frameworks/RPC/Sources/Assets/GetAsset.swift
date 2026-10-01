/// A DAS request for one known asset, such as the native mint's SOL image.
public struct GetAsset: RPCRequest {
    /// The DAS method for retrieving one asset's metadata.
    public static let method = "getAsset"
    /// The provider-neutral asset returned by DAS.
    public typealias Response = Asset
    /// The asset identifier to look up.
    public let id: String
    private let options = Options()

    /// Creates a metadata lookup for an asset identifier.
    /// - Parameter id: The asset's mint address or DAS identifier.
    public init(id: String) { self.id = id }

    private struct Options: Encodable, Sendable {
        let showCollectionMetadata = true
        let showUnverifiedCollections = true
    }
}
