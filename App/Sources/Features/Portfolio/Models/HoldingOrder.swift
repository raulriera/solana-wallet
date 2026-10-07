import Foundation
import Portfolio

/// Orders a wallet's holdings for display.
nonisolated enum HoldingOrder {
    /// Puts known values from highest to lowest, then holdings without a value; native SOL sorts like any token.
    ///
    /// Values in different currencies can't be compared without conversion, so mixed quote currencies
    /// keep the provider's order. Equal values also keep the provider's order.
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
