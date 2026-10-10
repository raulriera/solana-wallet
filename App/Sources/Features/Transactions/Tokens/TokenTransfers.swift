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
    /// Mint discovery determines associated addresses. A subsequent batch rereads
    /// the mint with the source, destination, and recipient accounts at one confirmed slot.
    /// A recipient owned by a token program must be a token account for the mint, which
    /// receives the tokens directly; any other nonexecutable recipient is a wallet that receives
    /// at its associated account. Epoch reads cannot precede that snapshot. No request is retried automatically.
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
                  source: Address? = nil, memo: String? = nil) async throws -> (transfer: TokenTransfer, slot: UInt64, rent: UInt64) {
        try Task.checkCancellation()
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let discovery = try await accounts(at: [mint])
        guard let discoveredAccount = discovery.value[0] else { throw TokenTransfersError.missingAccount(mint) }
        let discoveredMint = try TokenMint(address: mint, owner: Address(discoveredAccount.owner), data: discoveredAccount.data)
        let sourceAddress = try source ?? discoveredMint.associatedAccount(for: sender)
        let destinationAddress = try discoveredMint.associatedAccount(for: recipient)
        // The executable check also rejects a program as the recipient; tokens sent to its associated account are lost.
        let snapshot = try await accounts(at: [mint, sourceAddress, destinationAddress, recipient],
                                          minimumSlot: discovery.context.slot)
        guard let mintAccount = snapshot.value[0] else { throw TokenTransfersError.missingAccount(mint) }
        guard let sourceAccount = snapshot.value[1] else { throw TokenTransfersError.missingAccount(sourceAddress) }
        let currentMint = try TokenMint(address: mint, owner: Address(mintAccount.owner), data: mintAccount.data)
        guard currentMint.program == discoveredMint.program else { throw TokenError.accountMismatch }
        let tokenSource = try TokenAccount(address: sourceAddress, programOwner: Address(sourceAccount.owner), data: sourceAccount.data)
        let destinationAccount = snapshot.value[2]
        let owner: Address
        let destination: TokenAccount?
        if let recipientAccount = snapshot.value[3], TokenProgram(rawValue: recipientAccount.owner) != nil {
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
        var minimumSlot = snapshot.context.slot
        var epoch: UInt64?
        if currentMint.program == .token2022 {
            let observation = try await rpc.send(GetEpochInfo(commitment: .confirmed, minContextSlot: minimumSlot))
            try Task.checkCancellation()
            guard observation.absoluteSlot >= minimumSlot else { throw TokenTransfersError.inconsistentAccounts }
            minimumSlot = observation.absoluteSlot
            epoch = observation.epoch
        }
        let transfer = try TokenTransfer(sender: sender, recipient: owner, mint: currentMint, source: tokenSource,
                                         destination: destination, amount: amount, epoch: epoch, memo: memo)
        let rent: UInt64
        if let size = transfer.destinationAccountSize {
            let minimumBalance = max(1, try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: size)))
            let existingBalance = destinationAccount?.lamports ?? 0
            rent = existingBalance < minimumBalance ? minimumBalance - existingBalance : 0
        } else {
            rent = 0
        }
        try Task.checkCancellation()
        return (transfer, minimumSlot, rent)
    }

    /// Reads ordered account data while enforcing the requested count and ledger floor.
    ///
    /// - Parameters:
    ///   - addresses: The account addresses whose state must share one context.
    ///   - minimumSlot: The earliest acceptable slot, or `nil` for initial mint discovery.
    /// - Returns: Account observations, retaining absent accounts as `nil`.
    /// - Throws: An inconsistent-response, executable-account, RPC, or cancellation error.
    private func accounts(at addresses: [Address], minimumSlot: UInt64? = nil) async throws -> GetMultipleAccounts.Response {
        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses.map(\.value),
                                                            commitment: .confirmed, minContextSlot: minimumSlot))
        try Task.checkCancellation()
        guard response.value.count == addresses.count, response.context.slot >= (minimumSlot ?? 0) else {
            throw TokenTransfersError.inconsistentAccounts
        }
        guard !response.value.contains(where: { $0?.executable == true }) else { throw TokenError.invalidAccount }
        return response
    }
}
