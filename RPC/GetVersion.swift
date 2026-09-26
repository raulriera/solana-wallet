/// A request for the software version reported by a Solana node.
public struct GetVersion: RPCRequest {
    /// The JSON-RPC method name for retrieving node version information.
    public static let method = "getVersion"

    /// The node's software version and optional feature-set identifier.
    public struct Response: Decodable, Sendable {
        /// The Solana core software version reported by the node.
        public let solanaCore: String

        /// The node's feature-set identifier, or `nil` if the node omits it.
        public let featureSet: UInt32?

        /// Creates node version information.
        ///
        /// - Parameters:
        ///   - solanaCore: The Solana core software version reported by the node.
        ///   - featureSet: The node's feature-set identifier, or `nil` if unknown.
        public init(solanaCore: String, featureSet: UInt32?) {
            self.solanaCore = solanaCore
            self.featureSet = featureSet
        }

        /// The field names in the node's JSON result.
        private enum CodingKeys: String, CodingKey {
            case solanaCore = "solana-core"
            case featureSet = "feature-set"
        }
    }

    /// Creates a node-version request with no parameters.
    public init() {}

    /// Encodes an empty array of RPC parameters.
    ///
    /// - Parameter encoder: The encoder that receives the empty parameter array.
    public func encode(to encoder: any Encoder) throws {
        _ = encoder.unkeyedContainer()
    }
}
