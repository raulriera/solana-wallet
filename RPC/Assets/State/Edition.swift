extension Asset.State {
    /// An asset's edition supply information.
    public struct Edition: Codable, Sendable, Equatable {
        /// The maximum edition supply.
        public let maximumSupply: UInt64?
        /// The current edition supply.
        public let currentSupply: UInt64?
        /// The edition nonce.
        public let nonce: UInt8?

        /// Creates edition information without provider-specific field names.
        /// - Parameters:
        ///   - maximumSupply: The maximum edition supply.
        ///   - currentSupply: The current edition supply.
        ///   - nonce: The edition nonce.
        public init(maximumSupply: UInt64? = nil, currentSupply: UInt64? = nil, nonce: UInt8? = nil) {
            self.maximumSupply = maximumSupply
            self.currentSupply = currentSupply
            self.nonce = nonce
        }
    }
}
