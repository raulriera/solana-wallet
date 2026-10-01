extension Metadata {
    /// A creator's attributed share and on-chain verification flag.
    public struct Creator: Codable, Sendable, Equatable {
        /// The creator's public address.
        public let address: String
        /// The creator's percentage share.
        public let share: UInt8?
        /// Whether the creator attribution is verified; this is not an asset safety assessment.
        public let isVerified: Bool?

        /// Creates creator information without provider-specific field names.
        /// - Parameters:
        ///   - address: The creator's public address.
        ///   - share: The creator's percentage share.
        ///   - isVerified: Whether the creator attribution is verified; this is not an asset safety assessment.
        public init(address: String, share: UInt8? = nil, isVerified: Bool? = nil) {
            self.address = address
            self.share = share
            self.isVerified = isVerified
        }
    }
}
