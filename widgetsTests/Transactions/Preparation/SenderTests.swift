import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies Sender's preparation requirements using actual RPC clients.
struct SenderTests {
    /// Verifies a selected service cannot silently increase the requested priority fee.
    ///
    /// - Parameters:
    ///   - tier: The service tier selected for mainnet submission.
    ///   - requestedFee: A priority fee below the selected tier's requirement.
    ///   - minimumFee: The expected minimum total priority fee.
    @Test("Sender preparation rejects a priority fee below its requirement", arguments: [
        (Sender.Tier.swqosOnly, UInt64(0), UInt64(1)),
        (.max, UInt64(4_999), UInt64(5_000)),
    ])
    func senderRequiresReviewedPriorityFee(tier: Sender.Tier, requestedFee: UInt64, minimumFee: UInt64) async throws {
        let rpc = Solana()
        let sender = Sender(tier: tier)
        let transfer = try Transfer(sender: Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"),
                                    recipient: Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"), lamports: 1)
        let configuration = try Configuration(priorityFeeLamports: requestedFee,
                                               computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)

        await #expect(throws: Preparer.Failure.priorityFeeTooLow(minimumLamports: minimumFee)) {
            try await Preparer(rpc: rpc, rpcs: [rpc, sender]).prepare(transfer, configuration: configuration)
        }
    }

    /// Verifies a mainnet-only submission route adds no payment to real devnet preparation.
    ///
    /// - Parameter tier: The mainnet tier that must not affect devnet requests.
    @Test("devnet preparations omit mainnet Sender tips", .timeLimit(.minutes(1)), arguments: Sender.Tier.allCases)
    func devnetOmitsSenderTips(tier: Sender.Tier) async throws {
        let rpc = Solana(network: .devnet)
        let address = try Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T")
        let transfer = try Transfer(sender: address, recipient: address, lamports: 1)
        let configuration = try Configuration(priorityFeeLamports: 0, computeUnitLimit: 20_000,
                                               loadedAccountsDataSizeLimit: 65_536)

        let preparation = try await Preparer(rpc: rpc, rpcs: [rpc, Sender(tier: tier)])
            .prepare(transfer, configuration: configuration)

        #expect(preparation.network == .devnet)
        #expect(preparation.tips.isEmpty)
        #expect(preparation.transaction.instructions.count == 1)
        #expect(preparation.transaction.requests.priorityFeeLamports == 0)
    }
}
