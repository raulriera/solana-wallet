/// A DAS request for one asset.
public struct GetAsset: RPCRequest {
    /// The DAS method for retrieving one asset.
    public static let method = "getAsset"
    /// The provider-neutral asset returned by DAS.
    public typealias Response = Asset
    /// The asset identifier to look up.
    public let id: String

    /// Creates a lookup for an asset identifier.
    /// - Parameter id: The asset's mint address or DAS identifier.
    public init(id: String) { self.id = id }
}
