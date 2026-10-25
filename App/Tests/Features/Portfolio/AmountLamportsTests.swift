import Foundation
import Portfolio
import Testing
@testable import widgets

/// Checks that lamports show as SOL.
struct AmountLamportsTests {
    /// Lamports are SOL's smallest unit, nine decimal places below one SOL.
    @Test func `Lamports show as SOL`() {
        #expect(Amount(lamports: 1_500_000_000).formatted(locale: Locale(identifier: "en_US")) == "1.5")
        #expect(Amount(lamports: 5_000).formatted(locale: Locale(identifier: "en_US")) == "0.000005")
    }
}
