/// A DAS request for several known assets, answered in request order with `nil` for unknown identifiers.
struct GetAssetBatch: RPCRequest {
    /// The DAS method for retrieving several assets' metadata.
    static let method = "getAssetBatch"
    /// The assets in request order; DAS returns `null` for an identifier it doesn't know.
    typealias Response = [Asset?]
    /// The asset identifiers to look up, at most 1,000.
    let ids: [String]
}
