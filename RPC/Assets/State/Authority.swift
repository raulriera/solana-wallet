extension Asset.State {
    /// An asset authority and the scopes it controls.
    public struct Authority: Codable, Sendable, Equatable {
        /// The authority's public address.
        public let address: String
        /// The authority's reported scopes.
        public let scopes: [String]?

        /// Creates authority information without provider-specific field names.
        /// - Parameters:
        ///   - address: The authority's public address.
        ///   - scopes: The authority's reported scopes.
        public init(address: String, scopes: [String]? = nil) {
            self.address = address
            self.scopes = scopes
        }
    }
}
