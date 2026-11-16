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
        (Holding(asset: .token(usdc), balance: TokenAmount(amount: 1_234_567, decimals: 6), imageURL: nil,
                 valuation: dollars),
         PaymentToken(
             asset: .token(usdc),
             balance: TokenAmount(amount: 1_234_567, decimals: 6), price: 2)),
        (Holding(asset: .nativeSOL, balance: TokenAmount(amount: 1, decimals: 9), imageURL: nil, valuation: nil),
         PaymentToken(asset: .nativeSOL, balance: TokenAmount(amount: 1, decimals: 9), price: nil)),
    ])
    func `A holding with a balance becomes a token`(holding: Holding, token: PaymentToken) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == token)
    }

    @Test(arguments: [
        Holding(asset: .token(usdc), balance: TokenAmount(amount: 0, decimals: 6), imageURL: nil, valuation: nil),
        Holding(asset: .token(usdc), balance: nil, imageURL: nil, valuation: nil),
        Holding(asset: .token(usdc), balance: TokenAmount(amount: 5, decimals: 6),
                otherOwner: PaymentFixtures.lookAlike, imageURL: nil, valuation: nil),
    ])
    func `A holding with nothing to spend is left out`(holding: Holding) {
        #expect(PaymentToken(holding: holding, currencyCode: "USD") == nil)
    }

    @Test(arguments: [UInt64(1_000_000), 0])
    func `A holding becomes a price-less token of any balance`(amount: UInt64) {
        let holding = Holding(
            asset: .token(Self.usdc),
            balance: TokenAmount(amount: 5_000_000, decimals: 6),
            imageURL: nil,
            valuation: Self.dollars
        )

        let token = PaymentToken(holding: holding, balance: TokenAmount(amount: amount, decimals: 6), price: nil)

        #expect(token == PaymentToken(asset: .token(Self.usdc), balance: TokenAmount(amount: amount, decimals: 6),
                                      price: nil))
    }

    @Test func `A price in another currency is left out`() throws {
        let holding = Holding(asset: .nativeSOL, balance: TokenAmount(amount: 1, decimals: 9),
                              imageURL: nil, valuation: Self.dollars)

        let token = try #require(PaymentToken(holding: holding, currencyCode: "EUR"))

        #expect(token.price == nil)
    }
}
