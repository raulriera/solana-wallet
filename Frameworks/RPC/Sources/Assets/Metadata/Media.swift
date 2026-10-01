public import Foundation

extension Metadata {
    /// An asset media file and its optional delivery metadata.
    public struct Media: Codable, Sendable, Equatable {
        /// The original file URL.
        public let url: URL?
        /// The provider's optional CDN URL.
        public let cdnURL: URL?
        /// The file's declared media type.
        public let mimeType: String?

        /// Creates media information without provider-specific field names.
        /// - Parameters:
        ///   - url: The original file URL.
        ///   - cdnURL: The provider's optional CDN URL.
        ///   - mimeType: The file's declared media type.
        public init(url: URL? = nil, cdnURL: URL? = nil, mimeType: String? = nil) {
            self.url = url
            self.cdnURL = cdnURL
            self.mimeType = mimeType
        }
    }
}
