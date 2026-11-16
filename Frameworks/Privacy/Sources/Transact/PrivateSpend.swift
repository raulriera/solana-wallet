import ModularArithmetic
public import Redaction
public import Transactions

/// A proved transact that spends an account's notes into a private transfer, a public withdrawal,
/// or both, with the change back to the account.
public struct PrivateSpend: Sendable, Redacted {
    /// The destination of a spend.
    public enum Destination: Sendable {
        /// A private transfer to an owner's shielded address.
        case transfer(Recipient)
        /// A withdrawal to an owner's public balance: the owner's account for SOL, or for a token the owner's
        /// associated token account, which the spend opens when it doesn't exist.
        case withdrawal(Address)
        /// A private transfer of SOL to an owner's shielded address and a public withdrawal of `publicLamports` to the
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

    /// The instructions that open the accounts that the transact pays into, such as a token withdrawal's
    /// associated token account.
    let openings: [Instruction]

    /// The transact instruction.
    let instruction: Instruction

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
    let asset: PrivateAsset

    /// The spend's instructions in order: the account openings, then the transact.
    public var instructions: [Instruction] { openings + [instruction] }
}

extension PrivateSpend.Destination {
    /// Returns the instructions that open the accounts that a spend of an asset to the destination pays into, each of
    /// which succeeds without a change when the account exists.
    ///
    /// - Parameters:
    ///   - asset: The asset to move.
    ///   - payer: The account that signs and pays the new accounts' rent.
    /// - Returns: The instruction that opens the owner's associated token account for a token withdrawal, or none.
    /// - Throws: A ``Transactions/ValidationError`` if an address or the account's derivation is invalid.
    func openings(of asset: PrivateAsset, paidBy payer: Address) throws -> [Instruction] {
        switch (self, asset) {
        case (.withdrawal(let owner), .token(let token)):
            [try AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint, program: PrivateToken.program,
                                                         payer: payer)]
        case (.withdrawal, .nativeSOL), (.transfer, _), (.fundedTransfer, _):
            []
        }
    }

    /// Returns the private transfer and the public withdrawal that move an amount of an asset to the destination.
    ///
    /// - Parameters:
    ///   - amount: The amount to transfer or withdraw, in the asset's smallest unit.
    ///   - asset: The asset to move.
    /// - Returns: The transfer and the withdrawal, either of which can be `nil`.
    /// - Throws: A ``Transactions/ValidationError`` if a token account's derivation fails.
    func parts(
        moving amount: UInt64, of asset: PrivateAsset
    ) throws -> (transfer: TransactPlan.Transfer?, withdrawal: ExternalData.Withdrawal?) {
        switch self {
        case .transfer(let recipient):
            return (TransactPlan.Transfer(recipient: recipient, amount: amount), nil)
        case .withdrawal(let owner):
            let account =
                switch asset {
                case .nativeSOL: owner
                case .token(let token): try PrivateToken.program.associatedAccount(owner: owner, mint: token.mint)
                }
            return (nil, ExternalData.Withdrawal(recipient: account, amount: amount, asset: asset))
        case .fundedTransfer(let recipient, let publicLamports):
            return (
                TransactPlan.Transfer(recipient: recipient, amount: amount),
                ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: publicLamports, asset: .nativeSOL)
            )
        }
    }
}
