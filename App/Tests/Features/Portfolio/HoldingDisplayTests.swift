import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

struct HoldingDisplayTests {
    private static let providerLogo = URL(string: "https://cdn.example.com/logo.png")!
    private static let mint = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"
    private static let short = "4zMM…ncDU"

    @Test(arguments: [
        (Asset.nativeSOL, "SOL", "Solana"),
        (.token(.fixture(mint, decimals: 0, name: "", symbol: "")), short, short),
        (.token(.fixture(mint, decimals: 0)), short, short),
        (.token(.fixture(mint, decimals: 0, symbol: "JUP")), "JUP", "JUP"),
        (.token(.fixture(mint, decimals: 0, name: "Jupiter", symbol: "JUP")), "JUP",
         "Jupiter"),
    ])
    func `Names fall back to the asset's identity`(asset: Asset, shownSymbol: String, shownName: String) {
        #expect(asset.displaySymbol == shownSymbol)
        #expect(asset.displayName == shownName)
    }

    @Test(arguments: [
        (Valuation(pricePerUnit: 2, total: 4, currency: "USD") as Valuation?, true),
        (Valuation(pricePerUnit: 2, total: nil, currency: "USD"), false),
        (Valuation(pricePerUnit: 2, total: 4, currency: nil), false),
        (Valuation(pricePerUnit: 2, total: 4, currency: ""), false),
        (nil, false),
    ])
    func `Values need a total and a currency`(valuation: Valuation?, isKnown: Bool) {
        let holding = Holding.fixture(.fixture(Self.mint, decimals: 0), amount: nil, valuation: valuation)
        #expect((holding.knownValue != nil) == isKnown)
    }

    @Test(arguments: [
        (Asset.nativeSOL, "sol.png"),
        (.token(.fixture("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", decimals: 6)), "usdc.png"),
        (.token(.fixture("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", decimals: 6)), "usdt.png"),
    ])
    func `Bundled logos win over the provider's copy`(asset: Asset, file: String) throws {
        let holding = Holding(asset: asset, balance: nil, imageURL: Self.providerLogo, valuation: nil)
        let logo = try #require(holding.logoURL)
        #expect(logo.isFileURL)
        #expect(logo.lastPathComponent == file)
    }

    @Test
    func `Other tokens show the provider's copy when it has one`() {
        let listed = Holding.fixture(.fixture(Self.mint, decimals: 0), amount: nil, imageURL: Self.providerLogo)
        let unknown = Holding.fixture(.fixture(Self.mint, decimals: 0), amount: nil)
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
        let holding = Holding.fixture(.fixture(Self.mint, decimals: 0), amount: nil, valuation: valuation)
        #expect((holding.knownPrice != nil) == isKnown)
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
}
