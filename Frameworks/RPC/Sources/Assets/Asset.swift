public import Foundation

/// An indexed digital asset as DAS identifies it, with the provider's copy of its image.
public struct Asset: Decodable, Sendable {
    /// The asset identifier, which is the mint address for a fungible token.
    public let id: String
    /// The provider's HTTPS CDN copy of the asset's image, if available.
    public let imageURL: URL?

    /// Creates an asset from its identity and image.
    ///
    /// - Parameters:
    ///   - id: The asset identifier.
    ///   - imageURL: The provider's HTTPS CDN image, or `nil` if unavailable.
    public init(id: String, imageURL: URL?) {
        self.id = id
        self.imageURL = imageURL
    }
}
