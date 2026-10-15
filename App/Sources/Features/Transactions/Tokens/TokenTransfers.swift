import RPC
import Transactions

/// Resolves token instruction prerequisites through either first-party token program.
nonisolated struct TokenTransfers {
    private let rpc: any RPC

    /// Creates account discovery using the transaction workflow's read provider.
    /// - Parameter rpc: The provider for consistent token account observations.
    init(rpc: any RPC) { self.rpc = rpc }

    /// Reads consistent token account state for composable transfer instructions.
    ///
    /// One finalized batch reads the mint, the recipient, and both token programs' associated accounts, since the
    /// mint's program decides which of them apply. A recipient owned by a token program must be a token account for
    /// the mint, which receives the tokens directly; any other nonexecutable recipient is a wallet that receives at
    /// its associated account. A Token-2022 epoch read, which can't precede the batch, and a new destination's rent
    /// read then run together. No request is retried automatically.
    ///
    /// - Parameters:
    ///   - mint: The on-chain mint address.
    ///   - amount: The requested positive debit in raw token units.
    ///   - sender: The token owner authorizing the transfer.
    ///   - recipient: The receiving wallet, or a token account for the mint.
    ///   - source: A specific source account, or `nil` for the sender's associated account.
    ///   - memo: An optional memo placed immediately before the token transfer.
    /// - Returns: The validated instruction source, its minimum context, and estimated account deposit.
    /// - Throws: An account, token validation, construction, RPC, or cancellation error.
    @concurrent
    func transfer(mint: Address, amount: UInt64, from sender: Address, to recipient: Address,
                  source: Address?, memo: String? = nil) async throws -> (transfer: TokenTransfer, slot: UInt64, rent: UInt64) {
        try Task.checkCancellation()
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let programs = TokenProgram.allCases
        let sources = try source.map { [$0] } ?? programs.map { try $0.associatedAccount(owner: sender, mint: mint) }
        let destinations = try programs.map { try $0.associatedAccount(owner: recipient, mint: mint) }
        let addresses = [mint, recipient] + sources + destinations
        // The executable check also rejects a program as the recipient; tokens sent to its associated account are lost.
        let snapshot = try await accounts(at: addresses)
        // A repeated address, such as a mint entered as the recipient, has one state at the shared slot.
        let observed = Dictionary(zip(addresses, snapshot.value)) { first, _ in first }
        guard let mintAccount = observed[mint] ?? nil else { throw TokenTransfersError.missingAccount(mint) }
        let tokenMint = try TokenMint(address: mint, owner: Address(mintAccount.owner), data: mintAccount.data)
        // The mint's program picks which of the associated accounts derived above the transfer uses.
        guard let index = programs.firstIndex(of: tokenMint.program) else { throw TokenError.unsupportedProgram }
        let sourceAddress = source ?? sources[index]
        let destinationAddress = destinations[index]
        guard let sourceAccount = observed[sourceAddress] ?? nil else {
            throw TokenTransfersError.missingAccount(sourceAddress)
        }
        let tokenSource = try TokenAccount(address: sourceAddress, programOwner: Address(sourceAccount.owner), data: sourceAccount.data)
        let destinationAccount = observed[destinationAddress] ?? nil
        let owner: Address
        let destination: TokenAccount?
        if let recipientAccount = observed[recipient] ?? nil, TokenProgram(rawValue: recipientAccount.owner) != nil {
            // Decoding rejects mints and other token-program accounts; the transfer rejects other mints.
            let tokenAccount = try TokenAccount(address: recipient, programOwner: Address(recipientAccount.owner),
                                                data: recipientAccount.data)
            owner = tokenAccount.owner
            destination = tokenAccount
        } else {
            owner = recipient
            destination = try destinationAccount.flatMap {
                try TokenAccount(associatedAt: destinationAddress, programOwner: Address($0.owner), data: $0.data)
            }
        }
        // Token-2022 fees depend on the epoch, and a new destination needs its rent; neither read needs the other.
        async let epochRead = tokenMint.program == .token2022
            ? rpc.send(GetEpochInfo(minContextSlot: snapshot.context.slot)) : nil
        async let rentRead = destination == nil
            ? rpc.send(GetMinimumBalanceForRentExemption(dataLength: tokenMint.associatedAccountSize)) : nil
        let (epoch, minimumBalance) = try await (epochRead, rentRead)
        try Task.checkCancellation()
        var minimumSlot = snapshot.context.slot
        if let epoch {
            guard epoch.absoluteSlot >= minimumSlot else { throw TokenTransfersError.inconsistentAccounts }
            minimumSlot = epoch.absoluteSlot
        }
        let transfer = try TokenTransfer(sender: sender, recipient: owner, mint: tokenMint, source: tokenSource,
                                         destination: destination, amount: amount, epoch: epoch?.epoch, memo: memo)
        let deposit = minimumBalance.map { max(1, $0) } ?? 0
        let existingBalance = destinationAccount?.lamports ?? 0
        let rent = existingBalance < deposit ? deposit - existingBalance : 0
        return (transfer, minimumSlot, rent)
    }

    /// Reads ordered account data at one finalized context while enforcing the requested count.
    ///
    /// - Parameter addresses: The account addresses whose state must share one context.
    /// - Returns: Account observations, retaining absent accounts as `nil`.
    /// - Throws: An inconsistent-response, executable-account, RPC, or cancellation error.
    private func accounts(at addresses: [Address]) async throws -> GetMultipleAccounts.Response {
        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses.map(\.value)))
        try Task.checkCancellation()
        guard response.value.count == addresses.count else {
            throw TokenTransfersError.inconsistentAccounts
        }
        guard !response.value.contains(where: { $0?.executable == true }) else { throw TokenError.invalidAccount }
        return response
    }
}
