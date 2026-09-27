/// An instruction to transfer native SOL, expressed in integer lamports.
public struct Transfer: Sendable {
    /// The signing account that pays both the transfer and transaction fees.
    public let sender: Address
    /// The writable destination account.
    public let recipient: Address
    /// The number of lamports to transfer. One SOL equals one billion lamports.
    public let lamports: UInt64

    /// Creates a native SOL transfer with a positive amount.
    ///
    /// Sending to the same account is supported. The System Program cannot be a
    /// transfer account because this instruction invokes it as a read-only program.
    ///
    /// - Parameters:
    ///   - sender: The source account and fee payer.
    ///   - recipient: The destination account.
    ///   - lamports: The positive amount to transfer, excluding fees.
    /// - Throws: ``ValidationError/invalidAmount`` for zero lamports, or
    ///   ``ValidationError/programAddressAsTransferAccount`` for the System Program.
    public init(sender: Address, recipient: Address, lamports: UInt64) throws {
        guard lamports > 0 else { throw ValidationError.invalidAmount }
        guard sender.bytes.contains(where: { $0 != 0 }),
              recipient.bytes.contains(where: { $0 != 0 }) else {
            throw ValidationError.programAddressAsTransferAccount
        }
        self.sender = sender
        self.recipient = recipient
        self.lamports = lamports
    }
}
