public import Foundation

extension Metadata {
    /// A collection's identity and optional display metadata.
    public struct Collection: Codable, Sendable, Equatable {
        /// The collection identifier.
        public let id: String
        /// The collection's display name.
        public let name: String?
        /// The collection's ticker symbol.
        public let symbol: String?
        /// The collection's image URL.
        public let imageURL: URL?
        /// The collection's description.
        public let description: String?
        /// The collection's external URL.
        public let websiteURL: URL?
        /// The provider's collection verification flag, when supplied.
        public let isVerified: Bool?

        /// Creates collection information without provider-specific field names.
        /// - Parameters:
        ///   - id: The collection identifier.
        ///   - name: The collection's display name.
        ///   - symbol: The collection's ticker symbol.
        ///   - imageURL: The collection's image URL.
        ///   - description: The collection's description.
        ///   - websiteURL: The collection's external URL.
        ///   - isVerified: The provider's collection verification flag, when supplied.
        public init(
            id: String,
            name: String? = nil,
            symbol: String? = nil,
            imageURL: URL? = nil,
            description: String? = nil,
            websiteURL: URL? = nil,
            isVerified: Bool? = nil
        ) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.imageURL = imageURL
            self.description = description
            self.websiteURL = websiteURL
            self.isVerified = isVerified
        }
    }
}
