extension Asset.State {
    /// Ownership and delegation information reported for an asset.
    public struct Ownership: Codable, Sendable, Equatable {
        /// The reported owner's address.
        public let owner: String?
        /// The provider's ownership model.
        public let model: String?
        /// Whether the reported ownership is frozen.
        public let isFrozen: Bool?
        /// Whether the asset is delegated.
        public let isDelegated: Bool?
        /// The reported delegate's address.
        public let delegate: String?

        /// Creates ownership information without provider-specific field names.
        /// - Parameters:
        ///   - owner: The reported owner's address.
        ///   - model: The provider's ownership model.
        ///   - isFrozen: Whether the reported ownership is frozen.
        ///   - isDelegated: Whether the asset is delegated.
        ///   - delegate: The reported delegate's address.
        public init(
            owner: String? = nil,
            model: String? = nil,
            isFrozen: Bool? = nil,
            isDelegated: Bool? = nil,
            delegate: String? = nil
        ) {
            self.owner = owner
            self.model = model
            self.isFrozen = isFrozen
            self.isDelegated = isDelegated
            self.delegate = delegate
        }
    }
}
