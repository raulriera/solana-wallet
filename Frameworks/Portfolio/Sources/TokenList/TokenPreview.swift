public import Foundation
public import Transactions

/// A token found by its mint address, with its logo.
public struct TokenPreview: Sendable, Equatable {
    public let mint: Mint
    /// The provider's copy of the token's logo, or `nil` if it has none.
    public let logo: URL?

    /// Creates a token preview.
    ///
    /// - Parameters:
    ///   - mint: The token's mint.
    ///   - logo: The provider's copy of the logo, or `nil` if it has none.
    public init(mint: Mint, logo: URL?) {
        self.mint = mint
        self.logo = logo
    }
}
