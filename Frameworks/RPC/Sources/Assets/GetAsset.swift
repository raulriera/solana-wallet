/// A DAS request for one asset.
public struct GetAsset: RPCRequest {
    public static let method = "getAsset"
    public typealias Response = Asset
    public let id: String

    /// Creates a lookup for an asset identifier.
    ///
    /// - Parameter id: The asset's mint address or DAS identifier.
    public init(id: String) { self.id = id }
}
