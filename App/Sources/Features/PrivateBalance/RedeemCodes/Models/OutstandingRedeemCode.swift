/// A redeem code that an account created and whose one-time account still holds SOL.
nonisolated struct OutstandingRedeemCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    let record: RedeemCodeRecord
    let code: RedeemCode

    var description: String { "OutstandingRedeemCode" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }
}
