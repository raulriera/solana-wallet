import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

extension SubmissionTests {
    /// Verifies token-only recovery through both real devnet providers.
    ///
    /// The shared serialized suite protects retained wallet state. Token deposits are
    /// controlled by verified Vault recovery and returned to the sender even if discovery fails.
    /// - Parameter program: The token program whose native mint supplies the test balance.
    @Test("devnet discovery finds token-only accounts through both providers",
          .timeLimit(.minutes(3)), arguments: TokenProgram.allCases)
    func discoversTokenOnlyAccounts(_ program: TokenProgram) async throws {
        let rpcs = try devnetRPCs()
        let rpc = rpcs[0]
        let sender = Account(id: DevnetWallets.senderID, address: try await DevnetWallets.address(for: DevnetWallets.senderID))
        let recipient = Account(id: DevnetWallets.recipientID, address: try await DevnetWallets.address(for: DevnetWallets.recipientID))
        let recovery = try await DevnetWallets.store.recovery(for: recipient.id, reason: "Verify devnet discovery recovery")
        try #require(recovery.path == .solana)
        try #require(await Wallet().address(for: recovery.phrase, passphrase: recovery.passphrase,
                                          path: recovery.path) == recipient.address.value)
        let coordinator = try TransactionCoordinator(rpc: rpc, store: DevnetWallets.store, rpcs: rpcs)
        let mintAddress = try Address(program == .token ? "So11111111111111111111111111111111111111112"
                                                      : "9pan9bMn5HatX4EJdBwg9VgCa7Uz5HL8N1m5D3NdXejP")
        let mintRead = try await rpc.send(GetMultipleAccounts(addresses: [mintAddress.value]))
        let mintAccount = try #require(mintRead.value[0])
        let mint = try TokenMint(address: mintAddress, owner: Address(mintAccount.owner), data: mintAccount.data)
        let tokenAddress = try mint.associatedAccount(for: recipient.address)
        let oldAccount = try await rpc.send(GetMultipleAccounts(addresses: [tokenAddress.value]))
        let closeInstruction = try close(tokenAddress, owner: recipient.address, to: sender.address, program: program)
        if oldAccount.value[0] != nil {
            let review = try await coordinator.simulate([closeInstruction], using: [sender, recipient])
            try #require(await coordinator.confirm(review).outcome == .succeeded)
        }
        let initial = try await rpc.send(GetMultipleAccounts(addresses: [sender.address.value, recipient.address.value]))
        let initialSender = try #require(initial.value[0]).lamports
        try #require(initialSender >= 10_000_000, "Use the retained devnet sender; never replace its recovery")
        try #require((initial.value[1]?.lamports ?? 0) == 0, "Token-only discovery requires a zero-SOL recipient")
        let setup = try await coordinator.simulate([
            createAssociatedAccount(tokenAddress, owner: recipient.address, mint: mintAddress, program: program,
                                    payer: sender.address),
            SystemProgram.transfer(from: sender.address, to: tokenAddress, lamports: 1_000_000),
            Instruction(program: Address(program.rawValue), accounts: [
                .init(address: tokenAddress, isSigner: false, isWritable: true),
            ], data: Data([17])),
        ], using: sender)
        let setupFee = try #require(setup.fee)
        let funded = try await coordinator.confirm(setup)
        try #require(funded.outcome == .succeeded)

        var discoveryError: (any Error)?
        do {
            for client in rpcs {
                try #require(await Confirmer(rpc: client).confirm(funded.submission).outcome == .succeeded)
                let result = try await AccountDiscovery(rpc: client).discover(
                    for: recovery.phrase, passphrase: recovery.passphrase, indices: 0..<1)
                #expect(result.network == .devnet)
                let match = try #require(result.accounts.first { $0.account.address == recipient.address.value })
                #expect(match.account.path == recovery.path)
                #expect(match.evidence == .tokenAccount(program))
                print("Devnet \(program) token-only discovery verified through \(type(of: client))")
            }
        } catch { discoveryError = error }

        let cleanup = try await coordinator.simulate([closeInstruction], using: [sender, recipient])
        let cleanupFee = try #require(cleanup.fee)
        let closed = try await coordinator.confirm(cleanup)
        try #require(closed.outcome == .succeeded)
        let final = try await rpc.send(GetMultipleAccounts(
            addresses: [sender.address.value, recipient.address.value, tokenAddress.value], minContextSlot: closed.slot))
        #expect(final.value[0]?.lamports == initialSender - setupFee - cleanupFee)
        #expect((final.value[1]?.lamports ?? 0) == 0)
        #expect(final.value[2] == nil)
        print("Devnet discovery \(program) deposit returned: \(closed.submission.signature)")
        if let discoveryError { throw discoveryError }
    }

    /// Verifies the complete initial range, SOL discovery, and a previously used zero-balance account.
    @Test("devnet discovery scans the complete default range using retained recovery", .timeLimit(.minutes(3)))
    func discoversDefaultRange() async throws {
        let rpcs = try devnetRPCs()
        let sender = try await DevnetWallets.address(for: DevnetWallets.senderID)
        let recovery = try await DevnetWallets.store.recovery(for: DevnetWallets.senderID, reason: "Verify devnet account discovery")
        let full = try await AccountDiscovery(rpc: rpcs[0]).discover(for: recovery.phrase, passphrase: recovery.passphrase)
        #expect(full.indices == 0..<20)
        #expect(full.nextIndices == 20..<40)
        let match = try #require(full.accounts.first { $0.account.address == sender.value })
        #expect(match.account.path == recovery.path)
        #expect(match.evidence == .solBalance)
        let publicRead = try await AccountDiscovery(rpc: rpcs[1]).discover(
            for: recovery.phrase, passphrase: recovery.passphrase, indices: 0..<1)
        #expect(publicRead.accounts.first { $0.account.address == sender.value }?.evidence == .solBalance)

        // History is independent of token program; check it once per provider to avoid duplicate live reads.
        let recipient = try await DevnetWallets.address(for: DevnetWallets.recipientID)
        let recipientRecovery = try await DevnetWallets.store.recovery(
            for: DevnetWallets.recipientID, reason: "Verify devnet history-only discovery")
        for client in rpcs {
            let history = try await AccountDiscovery(rpc: client).discover(
                for: recipientRecovery.phrase, passphrase: recipientRecovery.passphrase, indices: 0..<1)
            let historyMatch = try #require(history.accounts.first { $0.account.address == recipient.value })
            #expect(historyMatch.account.path == recipientRecovery.path)
            #expect(historyMatch.evidence == .transactionHistory)
            print("Devnet history-only discovery verified through \(type(of: client))")
        }
    }
}
