import Foundation
import Portfolio
import Testing
import Transactions
@testable import widgets

struct PaymentTokenHoldingTests {
    nonisolated private static let dollars = Valuation(pricePerUnit: 2, total: nil, currency: "USD")
    nonisolated private static let usdc = Mint(address: PaymentFixtures.usdc, program: .token, decimals: 6,
                                               metadata: TokenMetadata(name: "USD Coin", symbol: "USDC"))

    @Test(arguments: [
        (Holding.fixture(usdc, amount: 1_234_567, valuation: dollars),
         PaymentToken(
             asset: .token(usdc),
             balance: TokenAmount(amount: 1_234_567, decimals: 6), price: 2)),
        (Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 1), imageURL: nil, valuation: nil),
         PaymentToken(asset: .nativeSOL, balance: TokenAmount(lamports: 1), price: nil)),
    ])
    func `A holding with a balance becomes a token`(holding: Holding, token: PaymentToken) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == token)
    }

    @Test(arguments: [
        Holding.fixture(usdc, amount: 0),
        Holding.fixture(usdc, amount: nil),
        Holding.fixture(usdc, amount: 5, otherOwner: PaymentFixtures.lookAlike),
    ])
    func `A holding with nothing to spend is left out`(holding: Holding) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == nil)
    }

    @Test func `A price in another currency is left out`() throws {
        let holding = Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 1),
                              imageURL: nil, valuation: Self.dollars)

        let token = try #require(PaymentToken(holding: holding, currencyCode: "EUR"))

        #expect(token.price == nil)
    }
}
