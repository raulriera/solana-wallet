extension Asset.State {
    /// Compression details reported for portfolio viewing.
    public struct Compression: Codable, Sendable, Equatable {
        /// Whether the asset is eligible for compression.
        public let isEligible: Bool?
        /// Whether the asset is compressed.
        public let isCompressed: Bool?
        /// The metadata data hash.
        public let dataHash: String?
        /// The creator hash.
        public let creatorHash: String?
        /// The asset hash.
        public let assetHash: String?
        /// The compression tree address.
        public let tree: String?
        /// The reported sequence.
        public let sequence: UInt64?
        /// The asset's leaf index.
        public let leafIndex: UInt64?

        /// Creates compression information without provider-specific field names.
        /// - Parameters:
        ///   - isEligible: Whether the asset is eligible for compression.
        ///   - isCompressed: Whether the asset is compressed.
        ///   - dataHash: The metadata data hash.
        ///   - creatorHash: The creator hash.
        ///   - assetHash: The asset hash.
        ///   - tree: The compression tree address.
        ///   - sequence: The reported sequence.
        ///   - leafIndex: The asset's leaf index.
        public init(
            isEligible: Bool? = nil,
            isCompressed: Bool? = nil,
            dataHash: String? = nil,
            creatorHash: String? = nil,
            assetHash: String? = nil,
            tree: String? = nil,
            sequence: UInt64? = nil,
            leafIndex: UInt64? = nil
        ) {
            self.isEligible = isEligible
            self.isCompressed = isCompressed
            self.dataHash = dataHash
            self.creatorHash = creatorHash
            self.assetHash = assetHash
            self.tree = tree
            self.sequence = sequence
            self.leafIndex = leafIndex
        }
    }
}
