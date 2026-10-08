public import Foundation

/// A token found by its mint address, with what a person checks before adding it.
public struct TokenPreview: Sendable, Equatable {
    /// The token, ready to add to an account's list.
    public let token: ListedToken
    /// The provider's copy of the token's logo, or `nil` when the provider has none.
    public let logo: URL?

    /// Creates a preview of a token and its logo.
    ///
    /// - Parameters:
    ///   - token: The token to show and add.
    ///   - logo: The provider's logo copy, or `nil` if unavailable.
    public init(token: ListedToken, logo: URL?) {
        self.token = token
        self.logo = logo
    }
}
