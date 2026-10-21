import Foundation

/// A redeem code that an account created, as this device keeps it: the code's index under the account's code root and
/// what its one-time account received.
///
/// The record holds no secret: the account's code root derives the code again from the index.
nonisolated struct RedeemCodeRecord: Codable, Equatable, Sendable {
    /// The index of the code's one-time account under the account's code root.
    let index: UInt32
    /// The lamports of the private note that the code's one-time account received.
    let amount: UInt64
    /// The public lamports that the code's one-time account received to pay for redeeming the code.
    let reserve: UInt64
    /// When the code's funding succeeded, or when this device found the code on chain.
    let created: Date
    /// The signature of the transaction that funded the code.
    let fundingSignature: String
}
