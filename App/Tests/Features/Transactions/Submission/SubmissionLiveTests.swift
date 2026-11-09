import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

@Suite(.serialized, .tags(.network))
struct SubmissionLiveTests {
    @Test(.timeLimit(.minutes(3)))
    func `Devnet submission delivers 0.001 SOL to the configured recipient`() async throws {
        let rpc = try LiveClients.client(network: .devnet)
        let wallets = try await DevnetWallets.configured()
        let sender = wallets.sender.address
        let recipient = wallets.recipient.address
        try await wallets.requireFunds(1_100_000, using: rpc)
        let coordinator: any TransactionCoordinating = try TransactionCoordinator(
            rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery))
        let initialAccounts = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value]))
        try #require(initialAccounts.value.count == 2)
        let senderBalance = try #require(initialAccounts.value[0]).lamports
        let recipientBalance = initialAccounts.value[1]?.lamports ?? 0
        let simulation = try await coordinator.simulate([
            SystemProgram.transfer(from: sender, to: recipient, lamports: 1_000_000),
            MemoProgram.memo("widgets devnet composition verification", signers: [recipient]),
        ], using: [wallets.sender, wallets.recipient])
        try #require(simulation.diagnostics.value.error == nil)
        let fee = try #require(simulation.fee)
        try #require(fee < 1_000_000)
        #expect(simulation.transaction.instructions.count == 2)
        #expect(simulation.transaction.signatures.count == 2)
        #expect(simulation.balanceChanges == [
            BalanceChange(owner: sender, asset: .sol, before: senderBalance, after: senderBalance - 1_000_000 - fee),
            BalanceChange(owner: recipient, asset: .sol, before: recipientBalance, after: recipientBalance + 1_000_000),
        ])

        let submission = try await coordinator.submit(simulation)
        let result = try await coordinator.confirm(submission)
        try #require(result.outcome == .succeeded)
        let slot = try await result.executionSlot(through: rpc)
        let accounts = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value], minContextSlot: slot))
        try #require(accounts.value.count == 2)
        #expect(accounts.value[0]?.lamports == senderBalance - 1_000_000 - fee)
        #expect(accounts.value[1]?.lamports == recipientBalance + 1_000_000)
    }

    @Test(.timeLimit(.minutes(2)))
    func `A devnet RPC rejects a signed transaction from an unfunded wallet`() async throws {
        let rpc = try LiveClients.client(network: .devnet)
        let wallet = Wallet()
        let phrase = try wallet.recoveryPhrase(wordCount: .twelve)
        let account = try #require(try await wallet.accounts(for: phrase, passphrase: "", paths: [.solana]).first)
        let address = try Address(account.address)
        let blockhash = try await rpc.send(GetLatestBlockhash())
        let message = try MessageBuilder().message(
            instructions: [SystemProgram.transfer(from: address, to: address, lamports: 1)], payer: address,
            recentBlockhash: blockhash.value.blockhash, configuration: configuration()
        )
        let signature = try await wallet.signature(for: message, using: phrase, expectedAddress: address.value,
                                                   passphrase: "", path: .solana)
        let bytes = try TransactionBuilder().transaction(byAdding: signature, for: address,
            to: TransactionBuilder().simulationTransaction(for: message)).serializedRepresentation

        let error = try await #require(throws: RPCError.self) {
            try await rpc.send(SendTransaction(transaction: bytes))
        }
        let simulation = try #require(error.preflightSimulation, "Received \(error)")
        #expect(simulation.error != nil)
    }

    @Test(.timeLimit(.minutes(3)), arguments: [
        (TokenProgram.token, "So11111111111111111111111111111111111111112"),
        (.token2022, "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP"),
    ])
    func `Devnet token transfers deliver balances to the configured recipient`(
        _ program: TokenProgram, mint: String
    ) async throws {
        let rpc = try LiveClients.client(network: .devnet)
        let wallets = try await DevnetWallets.configured()
        let sender = wallets.sender
        let recipient = wallets.recipient
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery))
        let mintAddress = try Address(mint)
        let source = try program.associatedAccount(owner: sender.address, mint: mintAddress)
        let destination = try program.associatedAccount(owner: recipient.address, mint: mintAddress)
        let accounts = try await rpc.send(GetMultipleAccounts(addresses: [source.value, destination.value]))
        try #require(accounts.value.count == 2)
        let initialBalances = try tokenAmounts(at: [source, destination], in: accounts)
        let sourceBalance = initialBalances[0]
        let destinationBalance = initialBalances[1]
        let amount: UInt64 = 1_000_000
        let wrapped = sourceBalance < amount ? 5 * amount : 0
        try await wallets.requireFunds(wrapped + 5_000_000, using: rpc)
        if wrapped > 0 {
            var setup: [Instruction] = []
            if accounts.value[0] == nil {
                setup.append(try createAssociatedAccount(source, owner: sender.address, mint: mintAddress,
                                                         program: program))
            }
            setup.append(try SystemProgram.transfer(from: sender.address, to: source, lamports: wrapped))
            setup.append(try Instruction(program: Address(program.rawValue), accounts: [
                .init(address: source, isSigner: false, isWritable: true)
            ], data: Data([17])))
            let setupReview = try await coordinator.simulate(setup, using: sender)
            let setupResult = try await coordinator.confirm(coordinator.submit(setupReview))
            try #require(setupResult.outcome == .succeeded)
        }
        let held = sourceBalance + wrapped

        let review = try await coordinator.transfer(amount, token: mintAddress, using: sender, to: recipient.address)
        let transfer = try #require(review.tokenTransfer)
        #expect(transfer.mint.program == program)
        #expect(transfer.amount == amount)
        #expect(transfer.createsDestination == (accounts.value[1] == nil))
        let rent = transfer.createsDestination
            ? try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: transfer.mint.associatedAccountSize))
            : 0
        #expect(review.destinationAccountRent == rent)
        let changes = try #require(review.balanceChanges)
        let fee = try #require(review.fee)
        let senderLamports = try #require(changes.first { $0.owner == sender.address && $0.asset == .sol })
        #expect(senderLamports.after == senderLamports.before - fee - rent)
        let token = BalanceChange.Asset.token(mint: mintAddress, decimals: transfer.mint.decimals)
        #expect(changes.contains(BalanceChange(owner: sender.address, asset: token, before: held,
                                               after: held - amount)))
        #expect(changes.contains(BalanceChange(owner: recipient.address, asset: token, before: destinationBalance,
                                               after: destinationBalance + amount)))
        let delivered = try await coordinator.confirm(coordinator.submit(review))
        try #require(delivered.outcome == .succeeded)
        let balances = try await tokenBalances([source, destination], through: rpc, after: delivered, program: program)
        #expect(balances == [held - amount, destinationBalance + amount])
    }

    private func tokenBalances(_ addresses: [Address], through rpc: some RPC, after confirmation: widgets.Confirmation,
                               program: TokenProgram) async throws -> [UInt64] {
        let slot = try await confirmation.executionSlot(through: rpc)
        let response = try await rpc.send(GetMultipleAccounts(addresses: addresses.map(\.value), minContextSlot: slot))
        #expect(Set(response.value.map { $0?.owner }) == [program.rawValue])
        return try tokenAmounts(at: addresses, in: response)
    }

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

    private func tokenAmounts(at addresses: [Address], in response: GetMultipleAccounts.Response) throws -> [UInt64] {
        try zip(addresses, response.value).map { address, account in
            guard let account else { return 0 }
            return try TokenAccount(address: address, programOwner: Address(account.owner), data: account.data).amount
        }
    }

    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)
    }
}
