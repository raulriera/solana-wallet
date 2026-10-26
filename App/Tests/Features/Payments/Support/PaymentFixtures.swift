import Foundation
import Transactions

// swift-format-ignore: NeverUseForceTry
/// Token mints for the payment tests, generated for them and owned by no one.
nonisolated enum PaymentFixtures {
    /// A dollar stablecoin's mint.
    static let usdc = try! Address("9PhDCJDrRGfciuPneWH8iUQAnBxsRepZrduusqroXb2H")
    /// The mint of a token without a known price.
    static let unpriced = try! Address("BnGdsNCPGX3ycLpgPHpStcajY5FtMDZAjiWHgrasiXDi")
    /// The mint of a token worth a tiny fraction of a cent.
    static let tiny = try! Address("4yTjnA9Hj8JvtWpp1eLPV575EM2sTHosTEVu74p9ejuL")
    /// The mint of a token with few decimals and a high price.
    static let coarse = try! Address("3Y3fit9UqsAHqs6rhSGaLxA4VUwWRPj9cfQKuTmbAGsw")
    /// The mint of a token whose price ends in half a cent.
    static let half = try! Address("8Gh4z5ndD3dLuKNvKX9fRbsFR4i188WRb9UAdEX5oumv")
    /// The mint of another token that shares a symbol with ``usdc``.
    static let lookAlike = try! Address("ChearUeBgrvrS2a421vA9nenKMQB1wADs9aAqPabeAaV")
}
