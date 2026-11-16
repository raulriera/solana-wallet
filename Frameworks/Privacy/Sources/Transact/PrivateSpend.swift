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

    /// The accounts that the transact pays into and the spend opens, such as a token withdrawal's associated token
    /// account, each with the instruction that opens it.
    let openings: [(account: Address, instruction: Instruction)]

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
    public var instructions: [Instruction] { openings.map(\.instruction) + [instruction] }

    /// The accounts that the spend opens when they don't exist, such as a token withdrawal's associated token
    /// account.
    public var openedAccounts: [Address] { openings.map(\.account) }
}

extension PrivateSpend.Destination {
    /// Returns the private transfer, the public withdrawal, and the account openings that move an amount of an asset to
    /// the destination.
    ///
    /// - Parameters:
    ///   - amount: The amount to transfer or withdraw, in the asset's smallest unit.
    ///   - asset: The asset to move.
    ///   - payer: The account that signs and pays the rent of the accounts that the spend opens.
    /// - Returns: The transfer and the withdrawal, either of which can be `nil`, and for a token withdrawal the owner's
    ///   associated token account with the instruction that opens it and succeeds without a change when it exists.
    /// - Throws: A ``Transactions/ValidationError`` if an address or a token account's derivation is invalid.
    func parts(moving amount: UInt64, of asset: PrivateAsset, paidBy payer: Address) throws -> (
        transfer: TransactPlan.Transfer?, withdrawal: ExternalData.Withdrawal?,
        openings: [(account: Address, instruction: Instruction)]
    ) {
        switch (self, asset) {
        case (.transfer(let recipient), _):
            return (TransactPlan.Transfer(recipient: recipient, amount: amount), nil, [])
        case (.withdrawal(let owner), .nativeSOL):
            return (nil, ExternalData.Withdrawal(recipient: owner, amount: amount, asset: asset), [])
        case (.withdrawal(let owner), .token(let token)):
            let account = try PrivateToken.program.associatedAccount(owner: owner, mint: token.mint)
            let opening = try AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint,
                                                                      program: PrivateToken.program, payer: payer)
            let withdrawal = ExternalData.Withdrawal(recipient: account, amount: amount, asset: asset)
            return (nil, withdrawal, [(account, opening)])
        case (.fundedTransfer(let recipient, let publicLamports), _):
            return (
                TransactPlan.Transfer(recipient: recipient, amount: amount),
                ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: publicLamports, asset: .nativeSOL),
                []
            )
        }
    }
}
