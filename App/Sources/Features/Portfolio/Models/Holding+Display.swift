import Foundation
import Portfolio
import Transactions

extension Holding {
    /// A holding without a balance that shows a looked-up token the way the token list will.
    /// - Parameter preview: The looked-up token and the provider's logo.
    nonisolated init(preview: TokenPreview) {
        self.init(id: .asset(preview.token.mint.value), amount: nil, name: preview.token.name,
                  symbol: preview.token.symbol, imageURL: preview.logo, valuation: nil)
    }

    /// Metadata's symbol, or the asset's identity when metadata has none.
    nonisolated var displaySymbol: String {
        if let symbol, !symbol.isEmpty { return symbol }
        switch id {
        case .nativeSOL: return "SOL"
        case .asset(let address): return address
        }
    }

    /// Metadata's name, or the same fallback as ``displaySymbol``.
    nonisolated var displayName: String {
        if let name, !name.isEmpty { return name }
        return id == .nativeSOL ? "Solana" : displaySymbol
    }

    /// The app's own logo for native SOL and the default tokens, otherwise the provider's copy, if any.
    nonisolated var logoURL: URL? {
        let bundledName: String? = switch id {
        case .nativeSOL: "sol"
        case .asset(DefaultToken.usdc.rawValue): "usdc"
        case .asset(DefaultToken.usdt.rawValue): "usdt"
        case .asset: nil
        }
        // A bundled logo needs no request, so it wins over the provider's copy.
        return bundledName.flatMap { Bundle.main.url(forResource: $0, withExtension: "png") } ?? imageURL
    }

    /// The whole holding's value and its quote currency, or `nil` when either is unknown.
    ///
    /// An unknown value is never zero.
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
