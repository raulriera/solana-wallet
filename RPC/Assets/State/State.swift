extension Asset {
    /// Provider-reported asset state for portfolio viewing, never transaction validation.
    public struct State: Codable, Sendable, Equatable {
        /// The token supply in smallest units.
        public let supply: UInt64?
        /// The token program address.
        public let tokenProgram: String?
        /// The reported mint authority.
        public let mintAuthority: String?
        /// The reported freeze authority.
        public let freezeAuthority: String?
        /// The asset authorities and their scopes.
        public let authorities: [Authority]?
        /// The provider's ownership and delegation information.
        public let ownership: Ownership?
        /// The royalty policy and sale information.
        public let royalties: Royalties?
        /// The edition supply information.
        public let edition: Edition?
        /// The asset's compression information.
        public let compression: Compression?
        /// Whether the asset is reported as burned.
        public let isBurned: Bool?

        /// Creates state information without provider-specific field names.
        /// - Parameters:
        ///   - supply: The token supply in smallest units.
        ///   - tokenProgram: The token program address.
        ///   - mintAuthority: The reported mint authority.
        ///   - freezeAuthority: The reported freeze authority.
        ///   - authorities: The asset authorities and their scopes.
        ///   - ownership: The provider's ownership and delegation information.
        ///   - royalties: The royalty policy and sale information.
        ///   - edition: The edition supply information.
        ///   - compression: The asset's compression information.
        ///   - isBurned: Whether the asset is reported as burned.
        public init(
            supply: UInt64? = nil,
            tokenProgram: String? = nil,
            mintAuthority: String? = nil,
            freezeAuthority: String? = nil,
            authorities: [Authority]? = nil,
            ownership: Ownership? = nil,
            royalties: Royalties? = nil,
            edition: Edition? = nil,
            compression: Compression? = nil,
            isBurned: Bool? = nil
        ) {
            self.supply = supply
            self.tokenProgram = tokenProgram
            self.mintAuthority = mintAuthority
            self.freezeAuthority = freezeAuthority
            self.authorities = authorities
            self.ownership = ownership
            self.royalties = royalties
            self.edition = edition
            self.compression = compression
            self.isBurned = isBurned
        }
    }
}
