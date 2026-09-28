import RPC
import Transactions

extension Preparer {
    /// Estimates the destination deposit without treating token amounts as SOL rent.
    ///
    /// - Parameter source: The validated local intent or external transaction context.
    /// - Returns: The deposit in lamports, zero for an existing token destination,
    ///   or `nil` for preparation paths whose account allocations aren't interpreted.
    /// - Throws: An RPC or cancellation error; failed estimates are never replaced with zero.
    func destinationAccountRent(for source: Preparation.Source) async throws -> UInt64? {
        guard case .token(let transfer, _, _, _) = source else { return nil }
        guard let size = transfer.destinationAccountSize else { return 0 }
        let rent = try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: size))
        // ATA creation always deposits at least one lamport, matching the program.
        return max(1, rent)
    }

    /// Reads consistent token account state and evaluates the exact transfer and service payments.
    ///
    /// Mint discovery determines associated addresses. A subsequent batch rereads
    /// the mint with both accounts at one confirmed slot. Epoch and blockhash reads
    /// cannot precede that snapshot. No request is retried automatically.
    ///
    /// - Parameters:
    ///   - mint: The on-chain mint address.
    ///   - amount: The requested positive debit in raw token units.
    ///   - sender: The token owner and sole signer paying SOL fees and rent.
    ///   - recipient: The wallet receiving tokens at its associated token account.
    ///   - configuration: The explicit fee and execution resource limits.
    ///   - source: A specific source account, or `nil` for the sender's associated account.
    ///   - memo: An optional memo placed immediately before the token transfer.
    /// - Returns: Immutable token review data, including simulation failures.
    /// - Throws: An account, token validation, construction, RPC, or cancellation error.
    @concurrent
    func prepareTokenTransfer(mint: Address, amount: UInt64, from sender: Address, to recipient: Address,
                              configuration: Configuration, source: Address? = nil,
                              memo: String? = nil) async throws -> Preparation {
        try Task.checkCancellation()
        guard amount > 0 else { throw ValidationError.invalidAmount }
        let tips = try serviceTips(from: sender, configuration: configuration)
        let network = rpc.network
        let discovery = try await accounts(at: [mint])
        guard let discoveredAccount = discovery.value[0] else { throw Failure.missingAccount(mint) }
        let discoveredMint = try TokenMint(address: mint, owner: Address(discoveredAccount.owner), data: discoveredAccount.data)
        let sourceAddress = try source ?? discoveredMint.associatedAccount(for: sender)
        let destinationAddress = try discoveredMint.associatedAccount(for: recipient)
        let snapshot = try await accounts(at: [mint, sourceAddress, destinationAddress], minimumSlot: discovery.context.slot)
        guard let mintAccount = snapshot.value[0] else { throw Failure.missingAccount(mint) }
        guard let sourceAccount = snapshot.value[1] else { throw Failure.missingAccount(sourceAddress) }
        let currentMint = try TokenMint(address: mint, owner: Address(mintAccount.owner), data: mintAccount.data)
        guard currentMint.program == discoveredMint.program else { throw TokenError.accountMismatch }
        let tokenSource = try TokenAccount(address: sourceAddress, programOwner: Address(sourceAccount.owner), data: sourceAccount.data)
        let destination = try snapshot.value[2].map {
            try TokenAccount(address: destinationAddress, programOwner: Address($0.owner), data: $0.data)
        }
        var minimumSlot = snapshot.context.slot
        var epoch: UInt64?
        if currentMint.program == .token2022 {
            let observation = try await rpc.send(GetEpochInfo(commitment: .confirmed, minContextSlot: minimumSlot))
            try Task.checkCancellation()
            guard observation.absoluteSlot >= minimumSlot else { throw Failure.inconsistentAccounts }
            minimumSlot = observation.absoluteSlot
            epoch = observation.epoch
        }
        let transfer = try TokenTransfer(sender: sender, recipient: recipient, mint: currentMint, source: tokenSource,
                                         destination: destination, amount: amount, epoch: epoch, memo: memo)
        let blockhash = try await rpc.send(GetLatestBlockhash(commitment: .confirmed, minContextSlot: minimumSlot))
        try Task.checkCancellation()
        guard blockhash.context.slot >= minimumSlot else { throw Failure.inconsistentAccounts }
        let message = try messageBuilder.message(for: transfer, tips: tips, recentBlockhash: blockhash.value.blockhash,
                                                 configuration: configuration)
        let transaction = try transactionBuilder.validateSignatures(in:
            transactionBuilder.simulationTransaction(for: message), for: sender
        )
        return try await evaluate(transaction, source: .token(transfer, tips, configuration, blockhash),
                                  signer: sender, network: network)
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
            throw Failure.inconsistentAccounts
        }
        guard !response.value.contains(where: { $0?.executable == true }) else { throw TokenError.invalidAccount }
        return response
    }
}
