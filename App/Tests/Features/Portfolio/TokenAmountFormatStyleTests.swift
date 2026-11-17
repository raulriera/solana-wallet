import Foundation
import Testing
import Transactions
@testable import widgets

struct TokenAmountFormatStyleTests {
    @Test(arguments: [
        (TokenAmount(amount: 1_250_000_000, decimals: 9), "1.25"),
        (TokenAmount(amount: 1_000_000_000, decimals: 9), "1"),
        (TokenAmount(amount: 1, decimals: 9), "0.000000001"),
        (TokenAmount(amount: .max, decimals: 6), "18,446,744,073,709.551615"),
        (TokenAmount(amount: 1, decimals: .max), "0." + String(repeating: "0", count: 254) + "1"),
    ])
    func `Amounts display exact asset quantities without trailing fractional zeros`(balance: TokenAmount,
                                                                                  expected: String) {
        #expect(TokenAmountFormatStyle().locale(Locale(identifier: "en_US")).format(balance) == expected)
    }

    @Test(arguments: [
        ("de_DE", "1.234,0005"),
        ("ar_EG", "١٬٢٣٤٫٠٠٠٥"),
    ])
    func `Amounts use the locale's grouping separators and digits`(identifier: String, expected: String) {
        let balance = TokenAmount(amount: 12_340_005, decimals: 4)

        #expect(TokenAmountFormatStyle().locale(Locale(identifier: identifier)).format(balance) == expected)
    }

    @Test(arguments: [
        (TokenAmount(lamports: 83_408_632), Asset.nativeSOL, "en_US", "0.083408632 SOL"),
        (TokenAmount(lamports: 1_234_500_000_000), .nativeSOL, "de_DE", "1.234,5 SOL"),
        (TokenAmount(amount: 2_500_000, decimals: 6), .token(.fixture(symbol: "USDC")), "de_DE", "2,5 USDC"),
    ])
    func `An amount of an asset shows its digits and the asset's symbol`(sent: TokenAmount, asset: Asset,
                                                                        locale: String, shown: String) {
        let style = TokenAmountFormatStyle.amount(of: asset).locale(Locale(identifier: locale))
        #expect(style.format(sent) == shown)
    }

    @Test(arguments: [
        (TokenAmount(amount: 9_999_123_456, decimals: 6), "9,999.123456"),
        (TokenAmount(amount: 1_100_000_000_000, decimals: 5), "11M"),
    ])
    func `Cards shorten balances from 10,000 up`(balance: TokenAmount, shown: String) {
        #expect(TokenAmountFormatStyle.abbreviatedAmount.locale(Locale(identifier: "en_US")).format(balance) == shown)
    }
}
