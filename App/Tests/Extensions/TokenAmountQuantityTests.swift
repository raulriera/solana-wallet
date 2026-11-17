import Foundation
import Testing
import Transactions
@testable import widgets

struct TokenAmountQuantityTests {
    @Test(arguments: [
        (Decimal(string: "1.5")!, UInt8(9), UInt64(1_500_000_000)),
        (Decimal(string: "0.000000001")!, 9, 1),
        (Decimal(string: "12.345678")!, 6, 12_345_678),
        (0, 9, 0),
        (42, 0, 42),
        (Decimal(string: "9223372036.854775808")!, 9, 9_223_372_036_854_775_808),
        (Decimal(string: "18446744073.709551615")!, 9, .max),
        (Decimal(string: "18446744073709551615")!, 0, .max),
    ])
    func `A quantity counts in the token's smallest units`(quantity: Decimal, decimals: UInt8, amount: UInt64) {
        #expect(TokenAmount(quantity, decimals: decimals) == TokenAmount(amount: amount, decimals: decimals))
    }

    @Test(arguments: [
        (Decimal(string: "0.0000000019")!, UInt8(9), UInt64(1)),
        (Decimal(string: "0.0000000009")!, 9, 0),
        (Decimal(string: "1.23456789")!, 6, 1_234_567),
        (Decimal(string: "0.9")!, 0, 0),
    ])
    func `Digits below the token's smallest unit are dropped, never rounded up`(quantity: Decimal, decimals: UInt8,
                                                                                amount: UInt64) {
        #expect(TokenAmount(quantity, decimals: decimals)?.amount == amount)
    }

    @Test(arguments: [
        (Decimal(string: "18446744073.709551616")!, UInt8(9)),
        (20_000_000_000, 9),
        (-1, 9),
        (1, 20),
        (0, 128),
        (1, 255),
    ])
    func `A negative quantity, or one that 64 bits or the decimals can't hold, has no amount`(quantity: Decimal,
                                                                                              decimals: UInt8) {
        #expect(TokenAmount(quantity, decimals: decimals) == nil)
    }

    @Test(arguments: [UInt8(0), 2, 6, 9, 18])
    func `Every balance converts to a quantity and back to the same amount`(decimals: UInt8) {
        var amounts: [UInt64] = [0, 1, 1 << 53 - 1, 1 << 53, 1 << 53 + 1, 1 << 63 - 1, 1 << 63, 1 << 63 + 1,
                                 .max - 1, .max]
        var power: UInt64 = 1
        for _ in 1...19 {
            power *= 10
            amounts += [power - 1, power, power + 1]
        }
        for amount in amounts {
            let balance = TokenAmount(amount: amount, decimals: decimals)
            #expect(TokenAmount(Decimal(balance), decimals: decimals) == balance)
        }
    }
}
