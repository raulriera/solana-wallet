import Privacy
import Transactions

/// A redeem or take-back of a code: the instructions that register the receiving account if it needs it and spend the
/// one-time account's notes to it, and the one-time account's public SOL that a trailing deposit sweeps into the
/// receiving account's private balance.
///
/// The one-time account pays every cost: the registration, the tree fees, and the network fee. Its lamports less the
/// registration and the tree fees are ``availableLamports``; charging the network fee leaves the deposit, so the
/// one-time account ends at exactly zero lamports. A deposit of zero lamports is left out.
nonisolated struct Redemption: Sendable {
    /// A network fee that a redemption can't be charged with.
    enum FeeError: Error, Equatable {
        /// The provider didn't report the transaction's network fee.
        case unknown
        /// The network fee of the charged transaction differs from the fee that it was charged with.
        case changed
    }

    /// The base fee of one signature, in lamports.
    static let signatureFee: UInt64 = 5_000

    /// The instructions before the trailing deposit: the registration, if any, and the spend of the notes.
    let instructions: [Instruction]
    /// The lamports of the one-time account's notes, which the spend transfers.
    let noteLamports: UInt64
    /// The one-time account's lamports less the registration and the tree fees.
    let availableLamports: UInt64
    /// The network fee and service tips that the one-time account pays, in lamports.
    let networkFee: UInt64
    /// The one-time account, which pays and deposits.
    let source: Address
    /// The receiving account's shielded address.
    let recipient: Recipient
    /// The tree that receives the deposit.
    let treeID: UInt16
    /// The index of the account's own code that the redemption takes back, or `nil` for a redeem.
    let takenBackIndex: UInt32?

    /// The lamports that the trailing deposit moves: the available lamports less the network fee.
    var depositLamports: UInt64 { availableLamports - networkFee }

    /// The lamports that the receiving account's private balance gains: the notes and the deposit.
    var lamports: UInt64 { noteLamports + depositLamports }

    /// The transaction's instructions: ``instructions`` and the trailing deposit, if it moves any lamports.
    ///
    /// - Throws: A validation error from the deposit instruction.
    var transactionInstructions: [Instruction] {
        get throws {
            guard depositLamports > 0 else { return instructions }
            return instructions + [try ShieldedPool.deposit(lamports: depositLamports, from: source, to: recipient,
                                                            treeID: treeID)]
        }
    }

    /// Creates a redemption before its network fee.
    /// - Parameters:
    ///   - instructions: The registration, if any, and the spend of the notes.
    ///   - noteLamports: The lamports that the spend transfers.
    ///   - availableLamports: The one-time account's lamports less the registration and the tree fees, from
    ///     ``availableLamports(of:registrationCost:treeFee:nullifierCount:)``.
    ///   - source: The one-time account.
    ///   - recipient: The receiving account's shielded address.
    ///   - treeID: The tree that receives the deposit.
    ///   - takenBackIndex: The index of the account's own code that this takes back, or `nil` for a redeem.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` if the notes and the available lamports together
    ///   exceed a 64-bit integer.
    init(instructions: [Instruction], noteLamports: UInt64, availableLamports: UInt64, source: Address,
         recipient: Recipient, treeID: UInt16, takenBackIndex: UInt32?) throws {
        guard !noteLamports.addingReportingOverflow(availableLamports).overflow else {
            throw Transactions.ValidationError.invalidAmount
        }
        self.instructions = instructions
        self.noteLamports = noteLamports
        self.availableLamports = availableLamports
        networkFee = 0
        self.source = source
        self.recipient = recipient
        self.treeID = treeID
        self.takenBackIndex = takenBackIndex
    }

    /// Copies a redemption with another network fee.
    /// - Parameters:
    ///   - redemption: The redemption.
    ///   - networkFee: A network fee of at most its available lamports.
    private init(_ redemption: Redemption, networkFee: UInt64) {
        instructions = redemption.instructions
        noteLamports = redemption.noteLamports
        availableLamports = redemption.availableLamports
        self.networkFee = networkFee
        source = redemption.source
        recipient = redemption.recipient
        treeID = redemption.treeID
        takenBackIndex = redemption.takenBackIndex
    }

    /// Charges the network fee to the trailing deposit, replacing any fee charged before.
    /// - Parameter fee: The network fee and service tips, in lamports.
    /// - Returns: The redemption whose deposit is the available lamports less the fee.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the fee exceeds the available lamports.
    func charging(_ fee: UInt64) throws -> Redemption {
        guard fee <= availableLamports else { throw PrivateBalanceError.codeUnderfunded }
        return Redemption(self, networkFee: fee)
    }

    /// Computes a one-time account's lamports that remain for the network fee and the trailing deposit.
    /// - Parameters:
    ///   - lamports: The one-time account's lamports.
    ///   - registrationCost: The lamports that registering the receiving account moves, or zero when it's registered.
    ///   - treeFee: The fee per nullifier of the tree that holds the notes.
    ///   - nullifierCount: The spend's ``Privacy/PrivateSpend/nullifierCount``.
    /// - Returns: The lamports less the registration and the tree fees.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the costs exceed the lamports or a 64-bit integer.
    static func availableLamports(of lamports: UInt64, registrationCost: UInt64, treeFee: UInt64,
                                  nullifierCount: Int) throws -> UInt64 {
        let (treeFees, multiplied) = treeFee.multipliedReportingOverflow(by: UInt64(nullifierCount))
        let (costs, added) = treeFees.addingReportingOverflow(registrationCost)
        guard !multiplied, !added, costs <= lamports else { throw PrivateBalanceError.codeUnderfunded }
        return lamports - costs
    }

    /// Computes the public lamports that a new code's one-time account receives to pay for redeeming it into any
    /// account: a registration record's rent, two signatures, and the tree fee of its one note.
    ///
    /// Covers base fees only, not Sender tips or priority fees. A code holds one note, so a redeem spends one input.
    ///
    /// - Parameters:
    ///   - rent: The rent of a registration record.
    ///   - treeFee: The fee per nullifier of the tree that receives the code's note.
    /// - Returns: The reserve, in lamports.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` if the reserve exceeds a 64-bit integer.
    static func reserve(rent: UInt64, treeFee: UInt64) throws -> UInt64 {
        let (fees, feesOverflow) = rent.addingReportingOverflow(2 * signatureFee)
        let (reserve, overflow) = fees.addingReportingOverflow(treeFee)
        guard !feesOverflow, !overflow else { throw Transactions.ValidationError.invalidAmount }
        return reserve
    }
}
