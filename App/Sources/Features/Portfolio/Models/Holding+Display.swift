import Foundation
import Portfolio

extension Holding {
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
