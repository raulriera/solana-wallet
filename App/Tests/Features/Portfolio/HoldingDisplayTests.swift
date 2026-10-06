import Foundation
import Portfolio
import Testing
@testable import widgets

/// Checks what the portfolio shows when metadata or prices are missing.
struct HoldingDisplayTests {
    /// Metadata wins; without it, native SOL keeps its own name and tokens show their mint address.
    /// - Parameters:
    ///   - id: The holding's identity.
    ///   - symbol: Metadata's symbol, if any.
    ///   - name: Metadata's name, if any.
    ///   - shownSymbol: The symbol the portfolio shows.
    ///   - shownName: The name the portfolio shows.
    @Test(arguments: [
        (Holding.Identity.nativeSOL, nil as String?, nil as String?, "SOL", "Solana"),
        (.asset("mint"), "", "", "mint", "mint"),
        (.asset("mint"), "JUP", nil, "JUP", "JUP"),
        (.asset("mint"), "JUP", "Jupiter", "JUP", "Jupiter"),
    ])
    func `Names fall back to the asset's identity`(id: Holding.Identity, symbol: String?, name: String?,
                                                   shownSymbol: String, shownName: String) {
        let holding = Holding(id: id, amount: nil, name: name, symbol: symbol, imageURL: nil, valuation: nil)
        #expect(holding.displaySymbol == shownSymbol)
        #expect(holding.displayName == shownName)
    }

    /// A value needs both a total and a currency; anything less is unknown, never zero.
    /// - Parameters:
    ///   - valuation: The provider's valuation, if any.
    ///   - isKnown: Whether the portfolio shows a value.
    @Test(arguments: [
        (Valuation(pricePerUnit: 2, total: 4, currency: "USD") as Valuation?, true),
        (Valuation(pricePerUnit: 2, total: nil, currency: "USD"), false),
        (Valuation(pricePerUnit: 2, total: 4, currency: nil), false),
        (Valuation(pricePerUnit: 2, total: 4, currency: ""), false),
        (nil, false),
    ])
    func `Values need a total and a currency`(valuation: Valuation?, isKnown: Bool) {
        let holding = Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: nil,
                              valuation: valuation)
        #expect((holding.knownValue != nil) == isKnown)
    }

    /// Exact amounts take their digits and separators from the locale that SwiftUI supplies.
    /// - Parameters:
    ///   - identifier: The text environment's locale.
    ///   - shown: The formatted amount.
    @Test(arguments: [("en_US", "1,234.5"), ("de_DE", "1.234,5")])
    func `Amounts use the text environment's locale`(identifier: String, shown: String) {
        let amount = Amount(units: 1_234_500_000_000, decimals: 9)
        #expect(AmountFormatStyle().locale(Locale(identifier: identifier)).format(amount) == shown)
    }
}
