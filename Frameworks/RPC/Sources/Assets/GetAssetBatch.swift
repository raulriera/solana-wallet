/// A DAS request for several assets, answered in request order with `nil` for unknown identifiers.
struct GetAssetBatch: RPCRequest {
    static let method = "getAssetBatch"
    typealias Response = [Asset?]
    /// The asset identifiers to look up, at most 1,000.
    let ids: [String]
}
