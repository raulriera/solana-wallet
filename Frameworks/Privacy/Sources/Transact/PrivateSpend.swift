import ModularArithmetic
public import Transactions

/// A proved transact that spends an account's notes into a private transfer, a public withdrawal,
/// or a transfer funded with a withdrawal, with the change back to the account.
///
/// ``NoteSyncState/spend(_:to:from:provider:)`` creates it. The account signs the instruction as the
/// fee payer. After the transaction succeeds, ``NoteSyncState/recording(_:signature:)`` removes the
/// spent notes and keeps ``receivedLamports`` pending until the indexer reports them. Descriptions
/// and reflection omit the values.
public struct PrivateSpend: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Where a spend sends its lamports.
    public enum Destination: Sendable {
        /// A private transfer to an owner's shielded address.
        case transfer(Recipient)
        /// A withdrawal to a public account.
        case withdrawal(Address)
        /// A private transfer to an owner's shielded address and, in the same transact, a public
        /// withdrawal of `publicLamports` to the owner's signing address, such as the SOL that the
        /// owner later pays its own fees with.
        ///
        /// The spend's notes cover both amounts; ``PrivateSpend/lamports`` is the transfer alone.
        /// If the signing address holds no lamports, a `publicLamports` below the network's
        /// rent-exempt minimum for an account without data fails on-chain.
        case fundedTransfer(Recipient, publicLamports: UInt64)
    }

    /// A spend that the account's notes can't cover.
    public enum ValidationError: Error, Equatable {
        /// The account's unspent notes in any one tree hold fewer lamports than the spend.
        case insufficientFunds
        /// A tree's notes cover the spend only with more than the 40 notes that one transaction
        /// spends.
        case tooManyNotes
        /// The indexer reported no tree for the spend's outputs.
        case noOutputTree
    }

    /// The transact instruction, which the account signs as the fee payer.
    public let instruction: Instruction

    /// The lamports that the spend transfers or withdraws: for a
    /// ``Destination/fundedTransfer(_:publicLamports:)``, the private transfer, without the public
    /// withdrawal.
    public let lamports: UInt64

    /// The lamports of the outputs that the account owns: the change, plus the transfer when it
    /// goes to the account's own shielded address.
    public let receivedLamports: UInt64

    /// The number of input slots that the transact publishes a nullifier for: every slot of its
    /// proof's shape, random padding included.
    ///
    /// The transact charges the fee payer each input tree's fee per nullifier, from
    /// ``ShieldedPool/feePerNullifier(treeID:using:)``, for each of these slots. A spend's inputs,
    /// padding included, come from one tree.
    public let nullifierCount: Int

    /// The tree that holds the spent notes, whose fee per nullifier the transact charges for each
    /// of the ``nullifierCount`` slots.
    public let inputTreeID: UInt16

    /// The nullifiers of the spent notes, in input order.
    let nullifiers: [Poseidon.Element]

    /// A description that omits the values.
    public var description: String { "PrivateSpend" }

    /// A debugging description that omits the values.
    public var debugDescription: String { description }

    /// A reflection view that omits the values.
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
