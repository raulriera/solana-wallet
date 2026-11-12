import Redaction

/// A redeem code that an account created and whose one-time account still holds SOL.
nonisolated struct OutstandingRedeemCode: Sendable, Equatable, Redacted {
    let record: RedeemCodeRecord
    let code: RedeemCode
}
