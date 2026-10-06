import Foundation
import Portfolio

/// Orders a wallet's holdings for display.
nonisolated enum HoldingOrder {
    /// Puts native SOL first, then known values from highest to lowest, then holdings without a value.
    ///
    /// Values in different currencies can't be compared without conversion, so mixed quote currencies
    /// keep the provider's order. Equal values also keep the provider's order.
    /// - Parameter holdings: A snapshot's holdings in the provider's order.
    /// - Returns: The same holdings in display order.
    static func sorted(_ holdings: [Holding]) -> [Holding] {
        let native = holdings.filter { $0.id == .nativeSOL }
        let tokens = holdings.filter { $0.id != .nativeSOL }
        let currencies = Set(holdings.compactMap(\.knownValue?.currency))
        guard currencies.count == 1 else { return native + tokens }

        let valued: [(offset: Int, total: Decimal, holding: Holding)] = tokens.enumerated()
            .compactMap { offset, holding in holding.knownValue.map { (offset, $0.total, holding) } }
        let ordered = valued.sorted { $0.total == $1.total ? $0.offset < $1.offset : $0.total > $1.total }
        return native + ordered.map(\.holding) + tokens.filter { $0.knownValue == nil }
    }
}
