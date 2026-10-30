import Foundation

/// A payment's token quantity and its value in a currency.
nonisolated struct PaymentAmount: Equatable, Sendable {
    let token: PaymentToken
    /// The token quantity, with at most the token's decimals.
    let quantity: Decimal
    /// What the quantity is worth in ``currencyCode``, or `nil` when the token has no price.
    let value: Decimal?
    /// The code of the currency that ``value`` is in.
    let currencyCode: String

    /// The quantity in the token's smallest units, such as lamports for SOL.
    var units: UInt64 {
        var exact = quantity * pow(10, token.decimals)
        var whole = Decimal()
        NSDecimalRound(&whole, &exact, 0, .down)
        return NSDecimalNumber(decimal: whole).uint64Value
    }
}
