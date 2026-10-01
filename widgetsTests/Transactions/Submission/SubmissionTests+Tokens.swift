import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

extension SubmissionTests {
    /// Verifies both first-party programs move wrapped devnet SOL and return deposits and funds.
    ///
    /// Wrapping and cleanup use the programs' published SyncNative and CloseAccount layouts.
    /// Both authorities are retained and reread from Vault before any account receives funds.
    /// - Parameter program: The first-party token program exercised through the same consumer API.
    @Test("devnet token transfers deliver balances and return funds and account deposits",
          .timeLimit(.minutes(3)), arguments: TokenProgram.allCases)
    func tokenTransfersReturnFunds(_ program: TokenProgram) async throws {
        let rpcs = try devnetRPCs()
        let rpc = rpcs[0]
        let sender = Account(id: DevnetWallets.senderID, recoveryID: DevnetWallets.senderID, address: try await DevnetWallets.address(for: DevnetWallets.senderID), index: 0)
        let recipient = Account(id: DevnetWallets.recipientID, recoveryID: DevnetWallets.recipientID, address: try await DevnetWallets.address(for: DevnetWallets.recipientID), index: 0)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: DevnetWallets.store, rpcs: rpcs)
        let mintAddress = try Address(program == .token ? "So11111111111111111111111111111111111111112"
                                                      : "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP")
        let mintRead = try await rpc.send(GetMultipleAccounts(addresses: [mintAddress.value]))
        let mintAccount = try #require(mintRead.value[0])
        let mint = try TokenMint(address: mintAddress, owner: Address(mintAccount.owner), data: mintAccount.data)
        let source = try mint.associatedAccount(for: sender.address)
        let destination = try mint.associatedAccount(for: recipient.address)
        let oldAccounts = try await rpc.send(GetMultipleAccounts(addresses: [source.value, destination.value]))
        // Recover deposits left by an interrupted earlier run, always to their controlled owners.
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
            let recovered = try await coordinator.confirm(review)
            try #require(recovered.outcome == .succeeded)
        }
        let initial = try await rpc.send(GetMultipleAccounts(addresses: [sender.address.value, recipient.address.value]))
        let initialSender = try #require(initial.value[0]).lamports
        let initialRecipient = initial.value[1]?.lamports ?? 0
        try #require(initialSender >= 10_000_000, "Retained sender needs 0.01 devnet SOL; never replace this wallet")
        let amount: UInt64 = 1_000_000
        let reserve: UInt64 = 1_000_000
        let setup = try await coordinator.simulate([
            createAssociatedAccount(source, owner: sender.address, mint: mintAddress, program: program),
            SystemProgram.transfer(from: sender.address, to: source, lamports: amount),
            Instruction(program: Address(program.rawValue), accounts: [
                .init(address: source, isSigner: false, isWritable: true)
            ], data: Data([17])),
            SystemProgram.transfer(from: sender.address, to: recipient.address, lamports: reserve),
        ], using: sender)
        let setupFee = try #require(setup.fee)
        let setupResult = try await coordinator.confirm(setup)
        try #require(setupResult.outcome == .succeeded)

        let review = try await coordinator.transfer(amount, token: mintAddress, using: sender, to: recipient.address)
        let transfer = try #require(review.tokenTransfer)
        #expect(transfer.mint.program == program)
        #expect(transfer.amount == amount)
        #expect(transfer.createsDestination)
        let rent = try await rpc.send(GetMinimumBalanceForRentExemption(dataLength: #require(transfer.destinationAccountSize)))
        #expect(review.destinationAccountRent == rent)
        let forwardFee = try #require(review.fee)
        let delivered = try await coordinator.confirm(review)
        try #require(delivered.outcome == .succeeded)
        let balances = try await tokenBalances([source, destination], through: rpcs, after: delivered, program: program)
        #expect(balances == [0, amount])
        print("Devnet \(program) delivery: \(delivered.submission.signature)")

        let refund = try await coordinator.transfer(amount, token: mintAddress, using: recipient, to: sender.address)
        #expect(refund.destinationAccountRent == 0)
        #expect(refund.tokenTransfer?.createsDestination == false)
        let refundFee = try #require(refund.fee)
        try #require(refundFee < reserve)
        let returned = try await coordinator.confirm(refund)
        try #require(returned.outcome == .succeeded)
        #expect(try await tokenBalances([source, destination], through: rpcs, after: returned, program: program) == [amount, 0])
        print("Devnet \(program) return: \(returned.submission.signature)")

        let cleanup = try await coordinator.simulate([
            close(source, owner: sender.address, to: sender.address, program: program),
            close(destination, owner: recipient.address, to: sender.address, program: program),
            SystemProgram.transfer(from: recipient.address, to: sender.address, lamports: reserve - refundFee),
        ], using: [sender, recipient])
        let cleanupFee = try #require(cleanup.fee)
        let closed = try await coordinator.confirm(cleanup)
        try #require(closed.outcome == .succeeded)
        let final = try await rpc.send(GetMultipleAccounts(
            addresses: [sender.address.value, recipient.address.value, source.value, destination.value], minContextSlot: closed.slot))
        #expect(final.value[0]?.lamports == initialSender - setupFee - forwardFee - refundFee - cleanupFee)
        #expect((final.value[1]?.lamports ?? 0) == initialRecipient)
        #expect(final.value[2] == nil && final.value[3] == nil)
        print("Devnet \(program) deposits recovered: \(closed.submission.signature)")
    }

    /// Verifies absent associated source accounts fail without fabricating a token balance.
    /// - Parameter program: The token program whose native mint supplies the real account context.
    @Test("devnet token transfers report a missing source account", arguments: TokenProgram.allCases)
    func missingTokenSourceIsReported(_ program: TokenProgram) async throws {
        let rpc = try devnetRPCs()[0]
        let sender = Account(id: DevnetWallets.senderID, recoveryID: DevnetWallets.senderID, address: try await DevnetWallets.address(for: DevnetWallets.senderID), index: 0)
        let mint = try Address(program == .token ? "So11111111111111111111111111111111111111112"
                                               : "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP")
        let coordinator = try TransactionCoordinator(rpc: rpc, store: DevnetWallets.store)
        // This random account is only queried; it never receives funds or signs a transaction.
        let absent = try Address(await Wallet().address(for: Wallet().recoveryPhrase()))
        await #expect {
            try await coordinator.transfer(1, token: mint, using: sender, to: sender.address,
                                           source: absent)
        } throws: { error in
            if case TokenTransfers.Failure.missingAccount = error { return true }
            return false
        }
    }

    /// Reads the exact delivered token balances through each configured real provider.
    /// - Parameters:
    ///   - addresses: The token accounts to observe.
    ///   - rpcs: The same-network clients used for broadcast.
    ///   - receipt: The confirmed transaction establishing the minimum observation slot.
    ///   - program: The expected owner program.
    /// - Returns: The observed raw balances, after asserting agreement between providers.
    /// - Throws: An RPC, account-decoding, or prerequisite error.
    private func tokenBalances(_ addresses: [Address], through rpcs: [any RPC], after receipt: widgets.Confirmation,
                               program: TokenProgram) async throws -> [UInt64] {
        var expected: [UInt64]?
        for rpc in rpcs {
            let confirmation = try await Confirmer(rpc: rpc).confirm(receipt.submission)
            try #require(confirmation.outcome == .succeeded)
            let response = try await rpc.send(GetMultipleAccounts(addresses: addresses.map(\.value), minContextSlot: confirmation.slot))
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
    ///   - owner: The retained wallet paying for and owning the account.
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

    /// Returns a native token account's lamports and rent deposit to a retained wallet.
    /// - Parameters:
    ///   - account: The account controlled by the selected authority.
    ///   - owner: The retained authority authorizing closure.
    ///   - destination: The retained wallet receiving the deposit and native balance.
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
