import Foundation
import Portfolio
import Transactions

extension Holding {
    /// Creates a holding without a balance for a looked-up token.
    ///
    /// - Parameter preview: The looked-up token and its logo.
    nonisolated init(preview: TokenPreview) {
        self.init(id: .asset(preview.token.mint.value), amount: nil, name: preview.token.name,
                  symbol: preview.token.symbol, imageURL: preview.logo, valuation: nil)
    }

    /// The metadata's symbol, or a fallback from the asset's identity, such as a short mint address.
    nonisolated var displaySymbol: String {
        if let symbol, !symbol.isEmpty { return symbol }
        switch id {
        case .nativeSOL: return "SOL"
        case .asset(let mint): return (try? Address(mint))?.formatted(.shortAddress) ?? mint
        }
    }

    /// The metadata's name, or a fallback from the asset's identity.
    nonisolated var displayName: String {
        if let name, !name.isEmpty { return name }
        return id == .nativeSOL ? "Solana" : displaySymbol
    }

    /// The bundled logo for native SOL and the default tokens, or the provider's logo for other tokens.
    nonisolated var logoURL: URL? {
        let bundledName: String? = switch id {
        case .nativeSOL: "sol"
        case .asset(DefaultToken.usdc.rawValue): "usdc"
        case .asset(DefaultToken.usdt.rawValue): "usdt"
        case .asset: nil
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
