import Privacy
import RPC
import Transactions

/// A private-balance transaction ready for review.
nonisolated struct PreparedPrivateTransaction: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    /// What a succeeded transaction changes in the account's private balance.
    enum Effect: Sendable {
        /// A deposit of lamports into the account's private balance.
        case deposit(UInt64)
        /// A spend of the account's notes into a private transfer or a public withdrawal.
        case spend(PrivateSpend)
        /// A spend that funds a new redeem code at an index of the code root, with a reserve in lamports.
        case createCode(PrivateSpend, index: UInt32, reserve: UInt64)
        /// A redeem or take-back of a code.
        case redeem(Redemption)
    }

    let instructions: [Instruction]
    /// The account whose private balance the transaction changes.
    let account: Account
    let network: Network
    let effect: Effect
    /// Whether the transaction also registers the account's private-balance keys.
    let registers: Bool
    /// The accounts that sign, in signing order, where the first pays.
    let authorities: [Authority]

    var description: String { "PreparedPrivateTransaction" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Returns the transaction with a redeem or take-back's network fee charged to its trailing deposit.
    ///
    /// - Parameter fee: The network fee and the service tip, in lamports.
    /// - Returns: The charged transaction.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the fee exceeds the SOL left for it, or a validation
    ///   error.
    func withNetworkFee(_ fee: UInt64) throws -> PreparedPrivateTransaction {
        guard case .redeem(let redemption) = effect else { return self }
        let charged = try redemption.charging(fee)
        return PreparedPrivateTransaction(instructions: try charged.transactionInstructions, account: account,
                                          network: network, effect: .redeem(charged), registers: registers,
                                          authorities: authorities)
    }
}
