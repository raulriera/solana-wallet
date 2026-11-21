import ModularArithmetic
import RPC
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
        /// The unspent notes of the asset don't cover the spend.
        case insufficientFunds
        /// The unspent notes of the asset cover the spend, but not within one transaction, which spends at most 40
        /// notes from at most 2 trees.
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

extension PrivateSpend {
    /// The private transfer, the public withdrawal, and the account openings that move an amount to a destination.
    struct Parts {
        /// The private transfer, or `nil` for none.
        let transfer: TransactPlan.Transfer?

        /// The public withdrawal, or `nil` for none.
        let withdrawal: ExternalData.Withdrawal?

        /// The accounts that the spend opens, such as a token withdrawal's associated token account, each with the
        /// instruction that opens it and succeeds without a change when it exists.
        let openings: [(account: Address, instruction: Instruction)]
    }

    /// Spends chosen notes into the parts of a spend, and proves the spend.
    ///
    /// - Parameters:
    ///   - notes: The notes to spend, whose nullifiers aren't queued.
    ///   - amount: The amount that the spend moves, in the asset's smallest unit.
    ///   - asset: The asset to spend.
    ///   - parts: The private transfer, the public withdrawal, and the account openings of the spend.
    ///   - outputTreeID: The ID of the tree that receives the spend's outputs.
    ///   - account: The account that owns the notes.
    ///   - prover: The prover of the account's network.
    ///   - generator: The source of the padding, blindings, and salt.
    /// - Throws: An error from the plan, the prover, or a proof check.
    init(
        spending notes: [ReceivedNote],
        moving amount: UInt64,
        of asset: PrivateAsset,
        parts: Parts,
        writingTo outputTreeID: UInt16,
        from account: ShieldedAccount,
        prover: some ProofProviding,
        using generator: inout some RandomNumberGenerator
    ) async throws {
        let plan = try TransactPlan(
            spending: notes.map(\.utxo), of: asset, sender: account, transfer: parts.transfer,
            withdrawal: parts.withdrawal, outputTreeID: outputTreeID, using: &generator
        )
        let sender = try account.recipient.owner
        let receivedAmount = plan.outputs.filter { $0.owner?.owner == sender }.reduce(0) { $0 + ($1.utxo?.amount ?? 0) }
        self.init(
            openings: parts.openings,
            instruction: try await plan.instruction(nullifierKey: account.nullifierKey, prover: prover),
            amount: amount, receivedAmount: receivedAmount,
            treeIDs: TransactPlan.writtenTreeIDs(inputs: plan.inputTreeIDs, output: plan.outputTreeID),
            nullifiers: notes.map(\.nullifier), asset: asset
        )
    }
}

extension PrivateSpend.Destination {
    /// Returns the private transfer, the public withdrawal, and the account openings that move an amount of an asset to
    /// the destination.
    ///
    /// - Parameters:
    ///   - amount: The amount to transfer or withdraw, in the asset's smallest unit.
    ///   - asset: The asset to move.
    ///   - payer: The account that signs and pays the rent of the accounts that the spend opens.
    /// - Returns: The parts of the spend.
    /// - Throws: A ``Transactions/ValidationError`` if an address or a token account's derivation is invalid.
    func parts(moving amount: UInt64, of asset: PrivateAsset, paidBy payer: Address) throws -> PrivateSpend.Parts {
        switch (self, asset) {
        case (.transfer(let recipient), _):
            return PrivateSpend.Parts(transfer: TransactPlan.Transfer(recipient: recipient, amount: amount),
                                      withdrawal: nil, openings: [])
        case (.withdrawal(let owner), .nativeSOL):
            let withdrawal = ExternalData.Withdrawal(recipient: owner, amount: amount, asset: asset)
            return PrivateSpend.Parts(transfer: nil, withdrawal: withdrawal, openings: [])
        case (.withdrawal(let owner), .token(let token)):
            let account = try PrivateToken.program.associatedAccount(owner: owner, mint: token.mint)
            let opening = try AssociatedTokenProgram.createIdempotent(owner: owner, mint: token.mint,
                                                                      program: PrivateToken.program, payer: payer)
            let withdrawal = ExternalData.Withdrawal(recipient: account, amount: amount, asset: asset)
            return PrivateSpend.Parts(transfer: nil, withdrawal: withdrawal, openings: [(account, opening)])
        case (.fundedTransfer(let recipient, let publicLamports), _):
            return PrivateSpend.Parts(
                transfer: TransactPlan.Transfer(recipient: recipient, amount: amount),
                withdrawal: ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: publicLamports,
                                                    asset: .nativeSOL),
                openings: []
            )
        }
    }
}
