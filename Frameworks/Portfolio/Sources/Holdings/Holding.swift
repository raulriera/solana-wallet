public import Foundation
public import Transactions

/// An asset held by a wallet, with optional descriptive and pricing information.
public struct Holding: Codable, Sendable, Equatable, Identifiable {
    /// An asset's identity within the snapshot's network.
    public enum Identity: Codable, Sendable, Hashable {
        /// Native SOL, distinct from wrapped SOL tokens.
        case nativeSOL
        /// A token, identified by its mint address.
        case asset(String)
    }

    /// The identity of the holding within its network.
    public let id: Identity
    /// The exact amount, or `nil` if the balance couldn't be read or belongs to ``otherOwner``.
    public let amount: Amount?
    /// The address that controls the token's account at the wallet's associated address, when it isn't the wallet.
    ///
    /// That address owns the account's tokens, so the holding has no amount.
    public let otherOwner: Address?
    /// The display name, if known.
    public let name: String?
    /// The ticker symbol, if known.
    public let symbol: String?
    /// The image URL, if the provider supplies one.
    public internal(set) var imageURL: URL?
    /// The available market valuation.
    public internal(set) var valuation: Valuation?

    /// Creates a holding from its identity and available portfolio data.
    ///
    /// - Parameters:
    ///   - id: The asset identity within the snapshot's network.
    ///   - amount: The exact amount, or `nil` if unknown.
    ///   - otherOwner: The address that controls the token's account instead of the wallet, or `nil`.
    ///   - name: The asset name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - imageURL: The image URL, or `nil` if unavailable.
    ///   - valuation: The available price information, or `nil` if unpriced.
    public init(id: Identity, amount: Amount?, otherOwner: Address? = nil, name: String?, symbol: String?,
                imageURL: URL?, valuation: Valuation?) {
        self.id = id
        self.amount = amount
        self.otherOwner = otherOwner
        self.name = name
        self.symbol = symbol
        self.imageURL = imageURL
        self.valuation = valuation
    }
}
