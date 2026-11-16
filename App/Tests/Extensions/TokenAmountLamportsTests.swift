import Foundation
import Testing
import Transactions
@testable import widgets

struct TokenAmountLamportsTests {
    @Test func `Lamports show as SOL`() {
        let style = TokenAmountFormatStyle().locale(Locale(identifier: "en_US"))
        #expect(style.format(TokenAmount(lamports: 1_500_000_000)) == "1.5")
        #expect(style.format(TokenAmount(lamports: 5_000)) == "0.000005")
    }
}
