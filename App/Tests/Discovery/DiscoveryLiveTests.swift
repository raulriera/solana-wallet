import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

extension SubmissionTests {
    /// Verifies SOL-funded recovery is found and the retained zero-SOL recipient is ignored.
    ///
    /// Each discovery performs one read-only lookup. No transfers, token setup, or funding are needed.
    @Test(.timeLimit(.minutes(1)))
    func `Devnet SOL discovery finds funded accounts and ignores zero-SOL accounts`() async throws {
        let rpcs = try devnetRPCs()
        let sender = try await DevnetWallets.address(for: DevnetWallets.senderID)
        let recipient = try await DevnetWallets.address(for: DevnetWallets.recipientID)
        let senderRecovery = try await DevnetWallets.store.recovery(
            for: DevnetWallets.senderID, reason: "Verify SOL-only devnet discovery")
        let recipientRecovery = try await DevnetWallets.store.recovery(
            for: DevnetWallets.recipientID, reason: "Verify zero-SOL accounts are ignored")

        for rpc in rpcs {
            // Establish current fixture balances independently of discovery's filtering.
            let balances = try await rpc.send(GetMultipleAccounts(addresses: [sender.value, recipient.value]))
            try #require((balances.value[0]?.lamports ?? 0) > 0)
            try #require((balances.value[1]?.lamports ?? 0) == 0)

            let funded = try await AccountDiscovery(rpc: rpc).discover(
                for: senderRecovery.phrase, passphrase: senderRecovery.passphrase)
            #expect(funded.network == .devnet)
            #expect(funded.indices == 0..<10)
            #expect(funded.nextIndices == 10..<20)
            let match = try #require(funded.accounts.first { $0.address == sender.value })
            #expect(match.path == .solana)

            let unfunded = try await AccountDiscovery(rpc: rpc).discover(
                for: recipientRecovery.phrase, passphrase: recipientRecovery.passphrase)
            #expect(!unfunded.accounts.contains { $0.address == recipient.value })
            print("Devnet SOL-only discovery verified through \(type(of: rpc))")
        }
    }
}
