public import Foundation

/// A token found by its mint address, with its logo.
public struct TokenPreview: Sendable, Equatable {
    public let token: ListedToken
    /// The provider's copy of the token's logo, or `nil` if it has none.
    public let logo: URL?

    /// Creates a token preview.
    ///
    /// - Parameters:
    ///   - token: The token.
    ///   - logo: The provider's copy of the logo, or `nil` if it has none.
    public init(token: ListedToken, logo: URL?) {
        self.token = token
        self.logo = logo
    }
}
