public import Transactions

/// A resolver that builds token transfers for either token program.
public struct TokenTransfers: Sendable {
    private let rpc: any RPC

    /// Creates a token transfer resolver.
    ///
    /// - Parameter rpc: The provider that reads token accounts.
    public init(rpc: any RPC) { self.rpc = rpc }

    /// Reads a token transfer's accounts and builds the transfer.
    ///
    /// - Parameters:
    ///   - reviewed: The token's mint as the person reviewed it, whose program and decimals the mint account must match.
    ///   - amount: The amount in raw token units.
    ///   - sender: The token owner that authorizes the transfer.
    ///   - recipient: The receiving wallet, or a token account for the mint.
    ///   - source: The token account to pay from, or `nil` for the sender's associated account.
    ///   - memo: The memo before the transfer, or `nil` for none.
    /// - Returns: The transfer, the minimum slot for later reads, and the new destination's rent in lamports.
    /// - Throws: ``Transactions/TokenError/accountMismatch`` if the mint account's program or decimals differ from the
    ///   reviewed mint, or an account, token validation, construction, RPC, or cancellation error.
    @concurrent
    public func transfer(mint reviewed: Mint, amount: UInt64, from sender: Address, to recipient: Address,
                  source: Address?, memo: String? = nil) async throws -> (transfer: TokenTransfer, slot: UInt64, rent: UInt64) {
        try Task.checkCancellation()
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let mint = reviewed.address
        let sourceAddress = try source ?? reviewed.program.associatedAccount(owner: sender, mint: mint)
        let destinationAddress = try reviewed.program.associatedAccount(owner: recipient, mint: mint)
        let addresses = [mint, recipient, sourceAddress, destinationAddress]
        let snapshot = try await accounts(at: addresses)
        let observed = Dictionary(zip(addresses, snapshot.value)) { first, _ in first }
        guard let mintAccount = observed[mint] ?? nil else { throw TokenTransfersError.missingAccount(mint) }
        let decoded = try Mint(address: mint, programAddress: Address(mintAccount.owner), data: mintAccount.data)
        guard decoded.program == reviewed.program, decoded.decimals == reviewed.decimals else {
            throw TokenError.accountMismatch
        }
        guard let sourceAccount = observed[sourceAddress] ?? nil else {
            throw TokenTransfersError.missingAccount(sourceAddress)
        }
        let sourceToken = try Token(address: sourceAddress, programAddress: Address(sourceAccount.owner),
                                    data: sourceAccount.data)
        let destinationAccount = observed[destinationAddress] ?? nil
        let owner: Address
        let destination: Token?
        if let recipientAccount = observed[recipient] ?? nil, TokenProgram(rawValue: recipientAccount.owner) != nil {
            let recipientToken = try Token(address: recipient, programAddress: Address(recipientAccount.owner),
                                           data: recipientAccount.data)
            owner = recipientToken.owner
            destination = recipientToken
        } else {
            owner = recipient
            destination = try destinationAccount.flatMap {
                try Token(associatedAt: destinationAddress, programAddress: Address($0.owner), data: $0.data)
            }
        }
        async let epochRead = decoded.program == .token2022
            ? rpc.send(GetEpochInfo(minContextSlot: snapshot.context.slot)) : nil
        let accountSize = try decoded.associatedAccountSize
        async let rentRead = destination == nil
            ? rpc.send(GetMinimumBalanceForRentExemption(dataLength: accountSize)) : nil
        let (epoch, minimumBalance) = try await (epochRead, rentRead)
        try Task.checkCancellation()
        let transfer = try TokenTransfer(sender: sender, recipient: owner, mint: decoded, source: sourceToken,
                                         destination: destination, amount: amount, epoch: epoch?.epoch, memo: memo)
        let deposit = minimumBalance.map { max(1, $0) } ?? 0
        let existingBalance = destinationAccount?.lamports ?? 0
        let rent = existingBalance < deposit ? deposit - existingBalance : 0
        return (transfer, epoch?.absoluteSlot ?? snapshot.context.slot, rent)
    }

    /// Reads accounts at one finalized context.
    ///
    /// - Parameter addresses: The account addresses.
    /// - Returns: The accounts, with `nil` for missing ones.
    /// - Throws: An error from ``RPC/accounts(at:minContextSlot:)``, an executable-account error, or a
    ///   cancellation error.
    private func accounts(at addresses: [Address]) async throws -> GetMultipleAccounts.Response {
        let response = try await rpc.accounts(at: addresses.map(\.value))
        try Task.checkCancellation()
        guard !response.value.contains(where: { $0?.executable == true }) else { throw TokenError.invalidAccount }
        return response
    }
}
