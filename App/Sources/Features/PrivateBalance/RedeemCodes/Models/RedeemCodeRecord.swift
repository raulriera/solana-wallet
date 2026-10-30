import Foundation

/// A redeem code that an account created, as this device keeps it.
nonisolated struct RedeemCodeRecord: Codable, Equatable, Sendable {
    let index: UInt32
    /// The code's private SOL, in lamports.
    let amount: UInt64
    /// The code's public SOL that pays for redeeming it, in lamports.
    let reserve: UInt64
    /// When the code's funding succeeded or this device found the code.
    let created: Date
    let fundingSignature: String
}
