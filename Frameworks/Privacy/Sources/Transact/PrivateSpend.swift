import ModularArithmetic
public import Transactions

/// A proved transact that spends an account's notes into a private transfer, a public withdrawal,
/// or both, with the change back to the account.
public struct PrivateSpend: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The destination of a spend's lamports.
    public enum Destination: Sendable {
        /// A private transfer to an owner's shielded address.
        case transfer(Recipient)
        /// A withdrawal to a public account.
        case withdrawal(Address)
        /// A private transfer to an owner's shielded address and a public withdrawal of `publicLamports` to the
        /// owner's signing address.
        case fundedTransfer(Recipient, publicLamports: UInt64)
    }

    /// A spend that can't be built.
    public enum ValidationError: Error, Equatable {
        /// No one tree's unspent notes hold enough lamports for the spend.
        case insufficientFunds
        /// The spend needs more than the 40 notes that one transaction spends.
        case tooManyNotes
        case noOutputTree
    }

    public let instruction: Instruction

    /// The lamports that the spend transfers or withdraws, excluding a funded transfer's public withdrawal.
    public let lamports: UInt64

    /// The lamports of the outputs that the account owns: the change, and a transfer to its own shielded address.
    public let receivedLamports: UInt64

    /// The number of nullifiers that the transact publishes, padding included.
    public let nullifierCount: Int

    public let inputTreeID: UInt16

    /// The nullifiers of the spent notes, in input order.
    let nullifiers: [Poseidon.Element]

    public var description: String { "PrivateSpend" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
