import RPC
import Transactions

/// A resolver that builds token transfers for either token program.
nonisolated struct TokenTransfers {
    private let rpc: any RPC

    /// Creates a token transfer resolver.
    ///
    /// - Parameter rpc: The provider that reads token accounts.
    init(rpc: any RPC) { self.rpc = rpc }

    /// Reads a token transfer's accounts and builds the transfer.
    ///
    /// - Parameters:
    ///   - mint: The token mint.
    ///   - amount: The amount in raw token units.
    ///   - sender: The token owner that authorizes the transfer.
    ///   - recipient: The receiving wallet, or a token account for the mint.
    ///   - source: The token account to pay from, or `nil` for the sender's associated account.
    ///   - memo: The memo before the transfer, or `nil` for none.
    /// - Returns: The transfer, the minimum slot for later reads, and the new destination's rent in lamports.
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
        let snapshot = try await accounts(at: addresses)
        let observed = Dictionary(zip(addresses, snapshot.value)) { first, _ in first }
        guard let mintAccount = observed[mint] ?? nil else { throw TokenTransfersError.missingAccount(mint) }
        let tokenMint = try TokenMint(address: mint, owner: Address(mintAccount.owner), data: mintAccount.data)
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

    /// Reads accounts at one finalized context.
    ///
    /// - Parameter addresses: The account addresses.
    /// - Returns: The accounts, with `nil` for missing ones.
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
