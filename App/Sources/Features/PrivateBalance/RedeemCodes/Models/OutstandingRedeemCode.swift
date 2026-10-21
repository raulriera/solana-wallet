/// A redeem code that an account created and whose one-time account still holds SOL, with the code to share or take
/// back.
///
/// Descriptions and reflection omit the code and the record.
nonisolated struct OutstandingRedeemCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// What this device keeps about the code.
    let record: RedeemCodeRecord
    /// The code, which redeems or takes back its SOL.
    let code: RedeemCode

    /// A description that omits the values.
    var description: String { "OutstandingRedeemCode" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
