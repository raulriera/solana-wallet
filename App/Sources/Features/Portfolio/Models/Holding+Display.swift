import Foundation
import Portfolio
import Transactions

extension Holding {
    /// Creates a holding without a balance for a looked-up token.
    ///
    /// - Parameter preview: The looked-up token and its logo.
    nonisolated init(preview: TokenPreview) {
        self.init(asset: .token(preview.mint), balance: nil, imageURL: preview.logo, valuation: nil)
    }

    /// The bundled logo for native SOL and the default tokens, or the provider's logo for other tokens.
    nonisolated var logoURL: URL? {
        let bundledName: String? = switch id {
        case .nativeSOL: "sol"
        case .token(let mint):
            ["EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": "usdc",
             "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": "usdt"][mint.value]
        }
        return bundledName.flatMap { Bundle.main.url(forResource: $0, withExtension: "png") } ?? imageURL
    }

    /// The whole holding's value and its quote currency, or `nil` when either is unknown.
    nonisolated var knownValue: (total: Decimal, currency: String)? {
        guard let total = valuation?.total, let currency = valuation?.currency, !currency.isEmpty else { return nil }
        return (total, currency)
    }

    /// The price of one token and its quote currency, or `nil` when either is unknown.
    nonisolated var knownPrice: (price: Decimal, currency: String)? {
        guard let price = valuation?.pricePerUnit, let currency = valuation?.currency, !currency.isEmpty else {
            return nil
        }
        return (price, currency)
    }
}
