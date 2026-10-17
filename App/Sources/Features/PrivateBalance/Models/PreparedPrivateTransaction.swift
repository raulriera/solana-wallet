import Privacy
import RPC
import Transactions

/// A private-balance transaction ready for review: its ordered instructions, the account that signs and pays for them,
/// and what it changes in the account's private balance once it succeeds.
///
/// The instructions go through the shared transaction pipeline; ``PrivateBalancing/complete(_:with:)`` records the
/// confirmed outcome. Descriptions and reflection omit every value, including the proof and the amounts.
nonisolated struct PreparedPrivateTransaction: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// What a succeeded transaction changes in the account's private balance.
    enum Effect: Sendable {
        /// A deposit of lamports into the account's own private balance.
        case deposit(UInt64)
        /// A spend of the account's notes into a private transfer or a public withdrawal.
        case spend(PrivateSpend)
    }

    /// The ordered instructions of one transaction, which the account signs as the fee payer.
    let instructions: [Instruction]
    /// The account that signs and pays.
    let account: Account
    /// The network that the transaction runs on.
    let network: Network
    /// What the transaction changes once it succeeds.
    let effect: Effect
    /// Whether the transaction also registers the account's private-balance keys, before its first deposit.
    let registers: Bool

    /// A description that omits the values.
    var description: String { "PreparedPrivateTransaction" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
