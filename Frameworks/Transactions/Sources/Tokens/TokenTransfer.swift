/// A validated token transfer that the source account's owner authorizes.
public struct TokenTransfer: Sendable {
    /// The source account's owner, who signs the transfer.
    public let sender: Address
    /// The wallet that owns the destination account.
    public let recipient: Address
    public let mint: Mint
    public let source: Token
    /// The token account that receives the tokens.
    public let destination: Address
    /// The debit in base units, before any transfer fee.
    public let amount: UInt64
    /// The transfer fee the instruction asserts, or `nil` if the mint has none.
    public let expectedFee: UInt64?
    public let createsDestination: Bool
    public let memo: String?

    /// Creates a transfer after validating its accounts and extensions.
    ///
    /// - Parameters:
    ///   - sender: The source account's owner.
    ///   - recipient: The wallet that owns the destination account.
    ///   - mint: The token's mint.
    ///   - source: The source token account.
    ///   - destination: The recipient's token account, or `nil` to create the recipient's associated account.
    ///   - amount: The debit in base units, greater than zero.
    ///   - epoch: The current epoch, or `nil` for a mint without transfer fees.
    ///   - memo: A memo, or `nil` for none.
    /// - Throws: A ``TokenError`` for inconsistent or unsupported accounts, or ``ValidationError/invalidAmount``.
    public init(sender: Address, recipient: Address, mint: Mint, source: Token,
                destination: Token?, amount: UInt64, epoch: UInt64? = nil, memo: String? = nil) throws {
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let target = try destination?.address ?? mint.program.associatedAccount(owner: recipient, mint: mint.address)
        guard source.address != sender, mint.address != sender, recipient != mint.address, target != sender,
              source.address != mint.address, target != mint.address else { throw TokenError.accountMismatch }
        expectedFee = try mint.transferFee(amount: amount, epoch: epoch, createsDestination: destination == nil)
        try mint.validate(source, ownedBy: sender)
        if let destination { try mint.validate(destination, ownedBy: recipient) }
        guard source.amount >= amount else { throw TokenError.insufficientBalance }
        _ = try source.requiresMemo(receiving: false)
        if try destination?.requiresMemo(receiving: true) == true, memo?.isEmpty != false {
            throw TokenError.memoRequired
        }
        if let memo, memo.isEmpty || memo.utf8.count > 4_032 { throw TokenError.invalidMemo }
        self.sender = sender
        self.recipient = recipient
        self.mint = mint
        self.source = source
        self.destination = target
        self.amount = amount
        self.memo = memo
        createsDestination = destination == nil
    }
}
