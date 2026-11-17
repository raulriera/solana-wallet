public import Foundation
public import Transactions

/// An asset that a wallet holds, with its balance and valuation.
public struct Holding: Codable, Sendable, Equatable, Identifiable {
    public let asset: Asset
    /// The balance, or `nil` if it couldn't be read or belongs to ``otherOwner``.
    public let balance: TokenAmount?
    /// The owner of the token account at the wallet's associated address, or `nil` if it's the wallet.
    public let otherOwner: Address?
    public internal(set) var imageURL: URL?
    public internal(set) var valuation: Valuation?

    public var id: Asset.ID { asset.id }

    /// Creates a holding.
    ///
    /// - Parameters:
    ///   - asset: The asset.
    ///   - balance: The balance, or `nil` if unknown.
    ///   - otherOwner: The owner of the token account when it isn't the wallet, or `nil`.
    ///   - imageURL: The image URL, or `nil` if none.
    ///   - valuation: The valuation, or `nil` if unpriced.
    public init(asset: Asset, balance: TokenAmount?, otherOwner: Address? = nil, imageURL: URL?,
                valuation: Valuation?) {
        self.asset = asset
        self.balance = balance
        self.otherOwner = otherOwner
        self.imageURL = imageURL
        self.valuation = valuation
    }
}
