import Redaction

/// An amount of an asset that a confirmed transaction gave the account, until a sync finds one of the transaction's notes
/// included or all of them spent.
struct PendingAmount: Sendable, Equatable, Codable, Redacted {
    let signature: String

    let asset: ConfidentialPlaintext.Asset

    /// The amount, in the asset's smallest unit.
    let amount: UInt64
}
