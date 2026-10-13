import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

extension SubmissionTests {
    /// Verifies both first-party programs deliver wrapped devnet SOL to the configured recipient.
    ///
    /// Wrapping and cleanup use the programs' published SyncNative and CloseAccount layouts. Each run
    /// first closes the token accounts the previous run left, so the delivered funds stay with the
    /// recipient. Both authorities are accounts of the devnet wallet your local configuration supplies.
    /// - Parameter program: The first-party token program exercised through the same consumer API.
    @Test(.timeLimit(.minutes(3)), arguments: TokenProgram.allCases)
    func `Devnet token transfers deliver balances to the configured recipient`(_ program: TokenProgram) async throws {
        let rpcs = try devnetRPCs()
        let rpc = rpcs[0]
        let wallets = try await DevnetWallets.configured()
        let sender = wallets.sender
        let recipient = wallets.recipient
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery), rpcs: rpcs)
        let mintAddress = try Address(program == .token ? "So11111111111111111111111111111111111111112"
                                                      : "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP")
        let mintRead = try await rpc.send(GetMultipleAccounts(addresses: [mintAddress.value]))
        let mintAccount = try #require(mintRead.value[0])
        let mint = try TokenMint(address: mintAddress, owner: Address(mintAccount.owner), data: mintAccount.data)
        let source = try mint.associatedAccount(for: sender.address)
        let destination = try mint.associatedAccount(for: recipient.address)
        let oldAccounts = try await rpc.send(GetMultipleAccounts(addresses: [source.value, destination.value]))
        // Close the token accounts the previous run left, returning each one's balance to its owner.
        var recoveryInstructions: [Instruction] = []
        if oldAccounts.value[0] != nil {
            recoveryInstructions.append(try close(source, owner: sender.address, to: sender.address, program: program))
        }
        if oldAccounts.value[1] != nil {
            recoveryInstructions.append(try close(destination, owner: recipient.address, to: recipient.address, program: program))
        }
        if !recoveryInstructions.isEmpty {
            let review = try await coordinator.simulate(recoveryInstructions,
                using: oldAccounts.value[1] == nil ? [sender] : [sender, recipient])
            let recovered = try await coordinator.confirm(coordinator.submit(review))
            try #require(recovered.outcome == .succeeded)
        }
        let initial = try await rpc.send(GetMultipleAccounts(addresses: [sender.address.value]))
        let initialSender = initial.value[0]?.lamports ?? 0
        try #require(initialSender >= 10_000_000, "Fund the configured devnet sender \(sender.address.value) with at least 0.01 SOL")
        let amount: UInt64 = 1_000_000
        let setup = try await coordinator.simulate([
            createAssociatedAccount(source, owner: sender.address, mint: mintAddress, program: program),
            SystemProgram.transfer(from: sender.address, to: source, lamports: amount),
            Instruction(program: Address(program.rawValue), accounts: [
                .init(address: source, isSigner: false, isWritable: true)
            ], data: Data([17])),
        ], using: sender)
        let setupResult = try await coordinator.confirm(coordinator.submit(setup))
        try #require(setupResult.outcome == .succeeded)

        let review = try await coordinator.transfer(amount, token: mintAddress, using: sender, to: recipient.address)
        let transfer = try #require(review.tokenTransfer)
        #expect(transfer.mint.program == program)
        #expect(transfer.amount == amount)
        #expect(transfer.createsDestination)
        let rent = try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: #require(transfer.destinationAccountSize)))
        #expect(review.destinationAccountRent == rent)
        let changes = try #require(review.balanceChanges)
        let fee = try #require(review.fee)
        let senderLamports = try #require(changes.first { $0.owner == sender.address && $0.asset == .sol })
        #expect(senderLamports.after == senderLamports.before - fee - rent)
        let token = BalanceChange.Asset.token(mint: mintAddress, decimals: transfer.mint.decimals)
        #expect(changes.contains(BalanceChange(owner: sender.address, asset: token, before: amount, after: 0)))
        #expect(changes.contains(BalanceChange(owner: recipient.address, asset: token, before: 0, after: amount)))
        let delivered = try await coordinator.confirm(coordinator.submit(review))
        try #require(delivered.outcome == .succeeded)
        let balances = try await tokenBalances([source, destination], through: rpcs, after: delivered, program: program)
        #expect(balances == [0, amount])
        print("Devnet \(program) delivery: \(delivered.submission.signature)")
    }

    /// Reads the exact delivered token balances through each configured real provider.
    /// - Parameters:
    ///   - addresses: The token accounts to observe.
    ///   - rpcs: The same-network clients used for broadcast, each watching the transaction again.
    ///   - receipt: The confirmed transaction whose receipt each client watches.
    ///   - program: The expected owner program.
    /// - Returns: The observed raw balances, after asserting agreement between providers.
    /// - Throws: An RPC, account-decoding, or prerequisite error.
    private func tokenBalances(_ addresses: [Address], through rpcs: [any RPC & SignatureEventProviding],
                               after receipt: widgets.Confirmation,
                               program: TokenProgram) async throws -> [UInt64] {
        var expected: [UInt64]?
        for rpc in rpcs {
            let confirmation = try await Confirmer(rpc: rpc).confirm(receipt.submission)
            try #require(confirmation.outcome == .succeeded)
            let slot = try await confirmation.executionSlot(through: rpc)
            let response = try await rpc.send(GetMultipleAccounts(addresses: addresses.map(\.value), minContextSlot: slot))
            let values = try zip(addresses, response.value).map { address, value in
                let account = try #require(value)
                #expect(account.owner == program.rawValue)
                return try TokenAccount(address: address, programOwner: Address(account.owner), data: account.data).amount
            }
            if let expected { #expect(values == expected) }
            expected = values
        }
        return try #require(expected)
    }

    /// Creates the controlled sender's native-token account for live test setup.
    /// - Parameters:
    ///   - address: The derived associated token address.
    ///   - owner: The configured sender paying for and owning the account.
    ///   - mint: The program's native mint.
    ///   - program: The token program receiving the account.
    /// - Returns: The official idempotent ATA instruction.
    /// - Throws: An address validation error.
    private func createAssociatedAccount(_ address: Address, owner: Address, mint: Address,
                                          program: TokenProgram) throws -> Instruction {
        try Instruction(program: Address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"), accounts: [
            .init(address: owner, isSigner: true, isWritable: true),
            .init(address: address, isSigner: false, isWritable: true),
            .init(address: owner, isSigner: false, isWritable: false),
            .init(address: mint, isSigner: false, isWritable: false),
            .init(address: Address("11111111111111111111111111111111"), isSigner: false, isWritable: false),
            .init(address: Address(program.rawValue), isSigner: false, isWritable: false),
        ], data: Data([1]))
    }

    /// Returns a native token account's lamports and rent deposit to the configured wallet.
    /// - Parameters:
    ///   - account: The account controlled by the selected authority.
    ///   - owner: The configured wallet's account authorizing closure.
    ///   - destination: The configured wallet's account receiving the deposit and native balance.
    ///   - program: The owning token program.
    /// - Returns: The official CloseAccount instruction.
    /// - Throws: An address validation error.
    private func close(_ account: Address, owner: Address, to destination: Address,
                       program: TokenProgram) throws -> Instruction {
        try Instruction(program: Address(program.rawValue), accounts: [
            .init(address: account, isSigner: false, isWritable: true),
            .init(address: destination, isSigner: false, isWritable: true),
            .init(address: owner, isSigner: true, isWritable: false),
        ], data: Data([9]))
    }
}
