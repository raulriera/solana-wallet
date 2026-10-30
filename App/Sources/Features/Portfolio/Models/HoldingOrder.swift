import Foundation
import Portfolio

/// Orders a wallet's holdings for display.
nonisolated enum HoldingOrder {
    /// Sorts holdings by known value from highest to lowest, then holdings without a value.
    ///
    /// - Parameter holdings: A snapshot's holdings in the provider's order.
    /// - Returns: The same holdings in display order.
    static func sorted(_ holdings: [Holding]) -> [Holding] {
        let currencies = Set(holdings.compactMap(\.knownValue?.currency))
        guard currencies.count == 1 else { return holdings }

        let valued: [(offset: Int, total: Decimal, holding: Holding)] = holdings.enumerated()
            .compactMap { offset, holding in holding.knownValue.map { (offset, $0.total, holding) } }
        let ordered = valued.sorted { $0.total == $1.total ? $0.offset < $1.offset : $0.total > $1.total }
        return ordered.map(\.holding) + holdings.filter { $0.knownValue == nil }
    }
}
