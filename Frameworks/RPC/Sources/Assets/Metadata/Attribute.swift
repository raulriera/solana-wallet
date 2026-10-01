extension Metadata {
    /// A metadata trait whose value retains its original JSON type.
    public struct Attribute: Codable, Sendable, Equatable {
        /// The trait's name.
        public let name: String?
        /// The trait's value; an explicit null remains distinct from an absent value.
        public let value: Value?
        /// An optional display hint supplied by the metadata.
        public let displayType: String?

        /// Creates attribute information without provider-specific field names.
        /// - Parameters:
        ///   - name: The trait's name.
        ///   - value: The trait's value; an explicit null remains distinct from an absent value.
        ///   - displayType: An optional display hint supplied by the metadata.
        public init(name: String? = nil, value: Value? = nil, displayType: String? = nil) {
            self.name = name
            self.value = value
            self.displayType = displayType
        }

        /// Decodes our stored trait while preserving explicit null values.
        /// - Parameter decoder: The decoder containing the canonical trait.
        /// - Throws: A decoding error for malformed stored fields.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            value = container.contains(.value) ? try container.decode(Value.self, forKey: .value) : nil
            displayType = try container.decodeIfPresent(String.self, forKey: .displayType)
        }

        private enum CodingKeys: String, CodingKey {
            case name, value, displayType
        }
    }
}
