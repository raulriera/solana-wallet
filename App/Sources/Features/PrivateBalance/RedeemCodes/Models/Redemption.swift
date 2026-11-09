import Privacy
import Transactions

/// A redeem or take-back that sweeps a code's one-time account into a private balance.
nonisolated struct Redemption: Sendable {
    /// An error in a redemption's network fee.
    enum FeeError: Error, Equatable {
        /// The provider didn't report the transaction's network fee.
        case unknown
        /// The network fee of the charged transaction differs from the fee that it was charged with.
        case changed
    }

    /// The base fee of one signature, in lamports.
    static let signatureFee: UInt64 = 5_000

    /// The instructions before the trailing deposit.
    let instructions: [Instruction]
    let noteLamports: UInt64
    /// The one-time account's lamports less the registration and the tree fees.
    let availableLamports: UInt64
    /// The network fee and the service tip, in lamports.
    let networkFee: UInt64
    /// The one-time account's address.
    let source: Address
    /// The receiving account's shielded address.
    let recipient: Recipient
    /// The tree that receives the deposit.
    let treeID: UInt16
    /// The index of the account's own code that this takes back, or `nil` for a redeem.
    let takenBackIndex: UInt32?

    /// The lamports that the trailing deposit moves.
    var depositLamports: UInt64 { availableLamports - networkFee }

    /// The lamports that the receiving account's private balance gains.
    var lamports: UInt64 { noteLamports + depositLamports }

    /// The transaction's instructions, with the trailing deposit if it moves any lamports.
    ///
    /// - Throws: A validation error from the deposit instruction.
    var transactionInstructions: [Instruction] {
        get throws {
            guard depositLamports > 0 else { return instructions }
            return instructions + [try ShieldedPool.deposit(lamports: depositLamports, from: source, to: recipient,
                                                            treeID: treeID)]
        }
    }

    /// Creates a redemption without a network fee.
    ///
    /// - Parameters:
    ///   - instructions: The registration, if any, and the spend of the notes.
    ///   - noteLamports: The lamports that the spend transfers.
    ///   - availableLamports: The one-time account's lamports less the registration and the tree fees.
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

    /// Creates a copy of a redemption with another network fee.
    ///
    /// - Parameters:
    ///   - redemption: The redemption to copy.
    ///   - networkFee: The network fee, in lamports.
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
    ///
    /// - Parameter fee: The network fee and the service tip, in lamports.
    /// - Returns: The redemption whose deposit is the available lamports less the fee.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the fee exceeds the available lamports.
    func charging(_ fee: UInt64) throws -> Redemption {
        guard fee <= availableLamports else { throw PrivateBalanceError.codeUnderfunded }
        return Redemption(self, networkFee: fee)
    }

    /// Returns a one-time account's lamports that remain for the network fee and the trailing deposit.
    ///
    /// - Parameters:
    ///   - lamports: The one-time account's lamports.
    ///   - registrationCost: The lamports that registering the receiving account moves, or zero when it's registered.
    ///   - treeFee: The fee of the trees that the spend writes, in lamports.
    /// - Returns: The lamports less the registration and the tree fees.
    /// - Throws: ``PrivateBalanceError/codeUnderfunded`` if the costs exceed the lamports or a 64-bit integer.
    static func availableLamports(of lamports: UInt64, registrationCost: UInt64, treeFee: UInt64) throws -> UInt64 {
        let (costs, overflow) = treeFee.addingReportingOverflow(registrationCost)
        guard !overflow, costs <= lamports else { throw PrivateBalanceError.codeUnderfunded }
        return lamports - costs
    }

    /// Returns the public lamports that pay for redeeming a new code into any account, including into another output
    /// tree whose fee is at most the code tree's.
    ///
    /// - Parameters:
    ///   - rent: The rent of a registration record, in lamports.
    ///   - treeFee: The fee of the tree that receives the code's note, in lamports.
    /// - Returns: The reserve: the rent, two signatures, and two tree fees, in lamports.
    /// - Throws: ``Transactions/ValidationError/invalidAmount`` if the reserve exceeds a 64-bit integer.
    static func reserve(rent: UInt64, treeFee: UInt64) throws -> UInt64 {
        let (treeFees, treeFeesOverflow) = treeFee.multipliedReportingOverflow(by: 2)
        let (fees, feesOverflow) = rent.addingReportingOverflow(2 * signatureFee)
        let (reserve, overflow) = fees.addingReportingOverflow(treeFees)
        guard !treeFeesOverflow, !feesOverflow, !overflow else { throw Transactions.ValidationError.invalidAmount }
        return reserve
    }
}
