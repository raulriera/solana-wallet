import ModularArithmetic
public import Transactions

/// A proved transact that spends an account's notes into a private transfer, a public withdrawal,
/// or both, with the change back to the account.
public struct PrivateSpend: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The destination of a spend.
    public enum Destination: Sendable {
        /// A private transfer to an owner's shielded address.
        case transfer(Recipient)
        /// A withdrawal of SOL to a public account.
        case withdrawal(Address)
        /// A withdrawal of a token to the owner's associated token account, which must exist.
        case tokenWithdrawal(PrivateToken, owner: Address)
        /// A private transfer to an owner's shielded address and a public withdrawal of `publicLamports` to the
        /// owner's signing address.
        case fundedTransfer(Recipient, publicLamports: UInt64)
    }

    /// A spend that can't be built.
    public enum ValidationError: Error, Equatable {
        /// The trees that one transaction spends from don't hold enough unspent notes of the asset for the spend.
        case insufficientFunds
        /// The spend needs more than the 40 notes that one transaction spends.
        case tooManyNotes
        case noOutputTree
    }

    public let instruction: Instruction

    /// The amount that the spend transfers or withdraws, in the asset's smallest unit, excluding a funded transfer's
    /// public withdrawal.
    public let amount: UInt64

    /// The amount of the outputs that the account owns, in the asset's smallest unit: the change, and a transfer to
    /// its own shielded address.
    public let receivedAmount: UInt64

    /// The IDs of the distinct trees that the transact writes.
    public let treeIDs: Set<UInt16>

    /// The nullifiers of the spent notes, in input order.
    let nullifiers: [Poseidon.Element]

    /// The asset that the spend spends.
    let asset: ConfidentialPlaintext.Asset

    public var description: String { "PrivateSpend" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension PrivateSpend.Destination {
    /// Returns the private transfer and the public withdrawal that move an amount to the destination.
    ///
    /// - Parameter amount: The amount to transfer or withdraw, in the asset's smallest unit.
    /// - Returns: The transfer and the withdrawal, either of which can be `nil`.
    /// - Throws: A ``Transactions/ValidationError`` if a token account's derivation fails.
    func parts(moving amount: UInt64) throws -> (transfer: TransactPlan.Transfer?, withdrawal: ExternalData.Withdrawal?) {
        switch self {
        case .transfer(let recipient): (TransactPlan.Transfer(recipient: recipient, lamports: amount), nil)
        case .withdrawal(let address): (nil, ExternalData.Withdrawal(recipient: address, amount: amount))
        case .tokenWithdrawal(let token, let owner): (nil, ExternalData.Withdrawal(
            recipient: try TokenProgram.token.associatedAccount(owner: owner, mint: token.mint), amount: amount, token: token
        ))
        case .fundedTransfer(let recipient, let publicLamports): (
            TransactPlan.Transfer(recipient: recipient, lamports: amount),
            ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: publicLamports)
        )
        }
    }
}
