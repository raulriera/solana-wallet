import Foundation
import Portfolio
import Testing
@testable import widgets

struct HoldingDisplayTests {
    private static let providerLogo = URL(string: "https://cdn.example.com/logo.png")!
    private static let mint = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"

    @Test(arguments: [
        (Holding.Identity.nativeSOL, nil as String?, nil as String?, "SOL", "Solana"),
        (.asset(mint), "", "", "4zMM…ncDU", "4zMM…ncDU"),
        (.asset(mint), nil, nil, "4zMM…ncDU", "4zMM…ncDU"),
        (.asset("mint"), "JUP", nil, "JUP", "JUP"),
        (.asset("mint"), "JUP", "Jupiter", "JUP", "Jupiter"),
    ])
    func `Names fall back to the asset's identity`(id: Holding.Identity, symbol: String?, name: String?,
                                                   shownSymbol: String, shownName: String) {
        let holding = Holding(id: id, amount: nil, name: name, symbol: symbol, imageURL: nil, valuation: nil)
        #expect(holding.displaySymbol == shownSymbol)
        #expect(holding.displayName == shownName)
    }

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

    @Test(arguments: [
        (Holding.Identity.nativeSOL, "sol.png"),
        (.asset(DefaultToken.usdc.rawValue), "usdc.png"),
        (.asset(DefaultToken.usdt.rawValue), "usdt.png"),
    ])
    func `Bundled logos win over the provider's copy`(id: Holding.Identity, file: String) throws {
        let holding = Holding(id: id, amount: nil, name: nil, symbol: nil, imageURL: Self.providerLogo, valuation: nil)
        let logo = try #require(holding.logoURL)
        #expect(logo.isFileURL)
        #expect(logo.lastPathComponent == file)
    }

    @Test
    func `Other tokens show the provider's copy when it has one`() {
        let listed = Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: Self.providerLogo,
                             valuation: nil)
        let unknown = Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: nil, valuation: nil)
        #expect(listed.logoURL == Self.providerLogo)
        #expect(unknown.logoURL == nil)
    }

    @Test(arguments: [
        (Valuation(pricePerUnit: 2, total: nil, currency: "USD") as Valuation?, true),
        (Valuation(pricePerUnit: nil, total: 4, currency: "USD"), false),
        (Valuation(pricePerUnit: 2, total: 4, currency: ""), false),
        (nil, false),
    ])
    func `Prices need a unit price and a currency`(valuation: Valuation?, isKnown: Bool) {
        let holding = Holding(id: .asset("mint"), amount: nil, name: nil, symbol: nil, imageURL: nil,
                              valuation: valuation)
        #expect((holding.knownPrice != nil) == isKnown)
    }

    @Test(arguments: [("en_US", "1,234.5"), ("de_DE", "1.234,5")])
    func `Amounts use the text environment's locale`(identifier: String, shown: String) {
        let amount = Amount(units: 1_234_500_000_000, decimals: 9)
        #expect(AmountFormatStyle().locale(Locale(identifier: identifier)).format(amount) == shown)
    }

    @Test(arguments: [
        (Decimal(string: "9999.99")!, "$9,999.99"), (Decimal(string: "10234.56")!, "$10.2K"),
        (Decimal(100_200), "$100.2K"), (Decimal(string: "1234567.89")!, "$1.2M"),
    ])
    func `Cards shorten values from 10,000 up`(total: Decimal, shown: String) {
        let style = ValueFormatStyle.abbreviatedValue(code: "USD").locale(Locale(identifier: "en_US"))
        #expect(style.format(total) == shown)
    }

    @Test
    func `Full values keep every digit`() {
        let style = ValueFormatStyle.value(code: "USD").locale(Locale(identifier: "en_US"))
        #expect(style.format(Decimal(string: "1234567.89")!) == "$1,234,567.89")
    }

    @Test(arguments: [
        (Decimal(string: "166.2345")!, "$166.23"), (Decimal(string: "0.4056018512541055")!, "$0.4056"),
        (Decimal(string: "0.99995")!, "$1.00"), (Decimal(string: "0.000021")!, "$0.000021"),
        (Decimal(string: "65000.12")!, "$65,000.12"),
    ])
    func `Prices show enough digits to be useful`(price: Decimal, shown: String) {
        #expect(ValueFormatStyle.price(code: "USD").locale(Locale(identifier: "en_US")).format(price) == shown)
    }

    @Test(arguments: [
        (Amount(units: 9_999_123_456, decimals: 6), "9,999.123456"), (Amount(units: 1_100_000_000_000, decimals: 5), "11M"),
    ])
    func `Cards shorten balances from 10,000 up`(amount: Amount, shown: String) {
        #expect(AmountFormatStyle.abbreviatedAmount.locale(Locale(identifier: "en_US")).format(amount) == shown)
    }
}
