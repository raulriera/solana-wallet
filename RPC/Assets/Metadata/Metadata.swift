public import Foundation

/// Descriptive asset information preserved independently of provider response formats.
public struct Metadata: Codable, Sendable, Equatable {
    /// The asset's human-readable description.
    public let description: String?
    /// The asset's external project or item link.
    public let websiteURL: URL?
    /// The original metadata document, without fetching it.
    public let metadataURL: URL?
    /// The available media files, preserving provider order.
    public let media: [Media]?
    /// The asset's named traits and their typed values.
    public let attributes: [Attribute]?
    /// The collections associated with this asset.
    public let collections: [Collection]?
    /// The attributed creators and their verification information.
    public let creators: [Creator]?
    /// The asset category, retaining unfamiliar categories.
    public let kind: String?
    /// The token metadata standard, when reported.
    public let tokenStandard: String?
    /// Whether the provider reports that the metadata can change.
    public let isMutable: Bool?

    /// Creates metadata information without provider-specific field names.
    /// - Parameters:
    ///   - description: The asset's human-readable description.
    ///   - websiteURL: The asset's external project or item link.
    ///   - metadataURL: The original metadata document, without fetching it.
    ///   - media: The available media files, preserving provider order.
    ///   - attributes: The asset's named traits and their typed values.
    ///   - collections: The collections associated with this asset.
    ///   - creators: The attributed creators and their verification information.
    ///   - kind: The asset category, retaining unfamiliar categories.
    ///   - tokenStandard: The token metadata standard, when reported.
    ///   - isMutable: Whether the provider reports that the metadata can change.
    public init(
        description: String? = nil,
        websiteURL: URL? = nil,
        metadataURL: URL? = nil,
        media: [Media]? = nil,
        attributes: [Attribute]? = nil,
        collections: [Collection]? = nil,
        creators: [Creator]? = nil,
        kind: String? = nil,
        tokenStandard: String? = nil,
        isMutable: Bool? = nil
    ) {
        self.description = description
        self.websiteURL = websiteURL
        self.metadataURL = metadataURL
        self.media = media
        self.attributes = attributes
        self.collections = collections
        self.creators = creators
        self.kind = kind
        self.tokenStandard = tokenStandard
        self.isMutable = isMutable
    }
}
