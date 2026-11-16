import Foundation
import Transactions
@testable import widgets

// swift-format-ignore: NeverUseForceTry
nonisolated enum PaymentFixtures {
    static let usdc = try! Address("9PhDCJDrRGfciuPneWH8iUQAnBxsRepZrduusqroXb2H")
    static let unpriced = try! Address("BnGdsNCPGX3ycLpgPHpStcajY5FtMDZAjiWHgrasiXDi")
    static let tiny = try! Address("4yTjnA9Hj8JvtWpp1eLPV575EM2sTHosTEVu74p9ejuL")
    static let coarse = try! Address("3Y3fit9UqsAHqs6rhSGaLxA4VUwWRPj9cfQKuTmbAGsw")
    static let half = try! Address("8Gh4z5ndD3dLuKNvKX9fRbsFR4i188WRb9UAdEX5oumv")
    static let lookAlike = try! Address("ChearUeBgrvrS2a421vA9nenKMQB1wADs9aAqPabeAaV")
    static let sol = PaymentToken(asset: .nativeSOL, balance: TokenAmount(amount: 2_000_000_000, decimals: 9),
                                  price: nil)
}
