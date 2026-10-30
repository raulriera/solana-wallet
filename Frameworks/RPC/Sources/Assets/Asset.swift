public import Foundation

/// A DAS asset with the provider's copy of its image.
public struct Asset: Decodable, Sendable {
    /// The asset identifier, which is the mint address for a fungible token.
    public let id: String
    /// The provider's HTTPS copy of the asset's image, or `nil` if unavailable.
    public let imageURL: URL?

    /// Creates an asset from its identity and image.
    ///
    /// - Parameters:
    ///   - id: The asset identifier.
    ///   - imageURL: The provider's HTTPS copy of the image, or `nil` if unavailable.
    public init(id: String, imageURL: URL?) {
        self.id = id
        self.imageURL = imageURL
    }
}
