/// A validated owner-authorized transfer for either first-party token program.
///
/// Account observations must come from the same network and a consistent ledger
/// context. Construction cannot establish provider honesty or prevent later state changes.
public struct TokenTransfer: Sendable {
    /// The token owner whose signature authorizes the transfer.
    public let sender: Address
    /// The wallet that owns the destination account.
    public let recipient: Address
    /// The mint and program governing this transfer.
    public let mint: TokenMint
    /// The source account, including support for non-associated token accounts.
    public let source: TokenAccount
    /// The token account receiving the tokens: an existing account the recipient owns, or its associated account.
    public let destination: Address
    /// The requested debit in integer base units, before any token transfer fee.
    public let amount: UInt64
    /// The token fee asserted by the instruction, or `nil` when the mint has none.
    public let expectedFee: UInt64?
    /// Whether the transaction includes idempotent destination-account creation, whose rent depends on the mint's
    /// ``TokenMint/associatedAccountSize``.
    public let createsDestination: Bool
    /// An optional UTF-8 memo placed immediately before the transfer.
    public let memo: String?

    /// Validates account relationships and the extensions needed for construction.
    ///
    /// - Parameters:
    ///   - sender: The source owner authorizing the token debit.
    ///   - recipient: The wallet that owns the destination account.
    ///   - mint: The initialized mint observed through RPC.
    ///   - source: The source account observed through RPC.
    ///   - destination: An initialized token account the recipient owns, or `nil` to create the recipient's associated account.
    ///   - amount: The positive base-unit debit, never a floating-point UI amount.
    ///   - epoch: The current ledger epoch for transfer fees, or `nil` for fee-free mints.
    ///   - memo: An optional memo; required when the destination enables incoming memos.
    /// - Throws: ``TokenError`` for inconsistent or unsupported account state, or
    ///   ``ValidationError/invalidAmount`` for a zero amount.
    public init(sender: Address, recipient: Address, mint: TokenMint, source: TokenAccount,
                destination: TokenAccount?, amount: UInt64, epoch: UInt64? = nil, memo: String? = nil) throws {
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let target = try destination?.address ?? mint.program.associatedAccount(owner: recipient, mint: mint.address)
        guard source.program == mint.program, source.mint == mint.address, source.owner == sender,
              source.address != sender, mint.address != sender, recipient != mint.address, target != sender,
              source.address != mint.address, target != mint.address else { throw TokenError.accountMismatch }
        if let destination {
            guard destination.program == mint.program, destination.mint == mint.address,
                  destination.owner == recipient else {
                throw TokenError.accountMismatch
            }
        }
        guard source.amount >= amount else { throw TokenError.insufficientBalance }
        _ = try source.requiresMemo(receiving: false)
        if try destination?.requiresMemo(receiving: true) == true, memo?.isEmpty != false {
            throw TokenError.memoRequired
        }
        if let memo, memo.isEmpty || memo.utf8.count > 4_032 { throw TokenError.invalidMemo }
        expectedFee = try mint.transferFee(amount: amount, epoch: epoch, createsDestination: destination == nil)
        try mint.validateExtensions(of: source)
        if let destination { try mint.validateExtensions(of: destination) }
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
