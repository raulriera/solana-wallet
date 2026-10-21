import Privacy
import RPC
import Transactions

/// A private-balance transaction ready for review: its ordered instructions, the authorities that sign them, the
/// account whose private balance it changes, and what it changes once it succeeds.
///
/// The instructions go through the shared transaction pipeline with ``authorities``, and
/// ``PrivateBalancing/complete(_:with:)`` records the confirmed outcome. A redeem or take-back sweeps its one-time
/// account to zero, so its network fee comes out of its trailing deposit: simulate it with
/// ``TransactionCoordinating/simulate(_:)``, which charges the fee, and complete the transaction that it returns.
/// Descriptions and reflection omit every value, including the proof and the amounts.
nonisolated struct PreparedPrivateTransaction: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// What a succeeded transaction changes in the account's private balance.
    enum Effect: Sendable {
        /// A deposit of lamports into the account's own private balance.
        case deposit(UInt64)
        /// A spend of the account's notes into a private transfer or a public withdrawal.
        case spend(PrivateSpend)
        /// A spend of the account's notes that funds a new redeem code: the code's note and its reserve go to the
        /// one-time account at the index of the account's code root.
        case createCode(PrivateSpend, index: UInt32, reserve: UInt64)
        /// A redeem or take-back that sweeps a code's one-time account into the account's private balance.
        case redeem(Redemption)
    }

    /// The ordered instructions of one transaction, which the first authority pays for.
    let instructions: [Instruction]
    /// The account whose private balance the transaction changes.
    let account: Account
    /// The network that the transaction runs on.
    let network: Network
    /// What the transaction changes once it succeeds.
    let effect: Effect
    /// Whether the transaction also registers the account's private-balance keys.
    let registers: Bool
    /// The saved and one-time accounts that sign, in signing order; the first pays.
    let authorities: [Authority]

    /// A description that omits the values.
    var description: String { "PreparedPrivateTransaction" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Charges a redeem or take-back's network fee to its trailing deposit, without proving again.
    ///
    /// The fee replaces any fee charged before. Other transactions pay their fee from their payer's public balance and
    /// return unchanged.
    /// - Parameter fee: The network fee and service tips, in lamports.
    /// - Returns: The transaction whose deposit is smaller by the fee and is left out at zero.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the fee exceeds the SOL left for it, or a validation
    ///   error from the deposit instruction.
    func withNetworkFee(_ fee: UInt64) throws -> PreparedPrivateTransaction {
        guard case .redeem(let redemption) = effect else { return self }
        let charged = try redemption.charging(fee)
        return PreparedPrivateTransaction(instructions: try charged.transactionInstructions, account: account,
                                          network: network, effect: .redeem(charged), registers: registers,
                                          authorities: authorities)
    }
}
