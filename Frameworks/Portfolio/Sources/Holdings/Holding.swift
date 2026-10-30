public import Foundation
public import Transactions

/// An asset that a wallet holds, with its details and valuation.
public struct Holding: Codable, Sendable, Equatable, Identifiable {
    /// The identity of an asset on a network.
    public enum Identity: Codable, Sendable, Hashable {
        case nativeSOL
        /// A token, identified by its mint address.
        case asset(String)
    }

    public let id: Identity
    /// The amount, or `nil` if the balance couldn't be read or belongs to ``otherOwner``.
    public let amount: Amount?
    /// The owner of the token account at the wallet's associated address, or `nil` if it's the wallet.
    public let otherOwner: Address?
    public let name: String?
    /// The ticker symbol.
    public let symbol: String?
    public internal(set) var imageURL: URL?
    public internal(set) var valuation: Valuation?

    /// Creates a holding.
    ///
    /// - Parameters:
    ///   - id: The asset's identity.
    ///   - amount: The amount, or `nil` if unknown.
    ///   - otherOwner: The owner of the token account when it isn't the wallet, or `nil`.
    ///   - name: The asset name, or `nil` if unknown.
    ///   - symbol: The ticker symbol, or `nil` if unknown.
    ///   - imageURL: The image URL, or `nil` if none.
    ///   - valuation: The valuation, or `nil` if unpriced.
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
