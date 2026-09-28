import Foundation
import RPC
import Testing
import Transactions
import Vault
@testable import widgets

/// Verifies exclusive strategy selection and preparation using actual RPC clients.
struct StrategyTests {
    /// Verifies disabling Sender retains ordinary clients only on the selected network.
    @Test("none selects all ordinary RPCs on the transaction network")
    func noneSelectsOrdinaryRPCs() throws {
        let clients = try TransactionCoordinator.Strategy.none.clients(for: .mainnet, from: [
            Solana(), HeliusRPC(apiKey: "test-key"), Solana(network: .devnet), Sender(tier: .premium),
        ])

        try #require(clients.count == 2)
        #expect(clients[0] is Solana)
        #expect(clients[1] is HeliusRPC)
        #expect(clients.allSatisfy { $0.network == .mainnet && $0.submissionRequirements == nil })
    }

    /// Verifies a Sender strategy replaces the supplied routes with its single client.
    ///
    /// - Parameters:
    ///   - strategy: The app's selected delivery strategy.
    ///   - tier: The expected concrete Sender tier.
    @Test("Sender strategies replace ordinary RPCs with one selected tier", arguments: [
        (TransactionCoordinator.Strategy.standard, Sender.Tier.standard),
        (.premium, .premium),
    ])
    func senderReplacesOrdinaryRPCs(strategy: TransactionCoordinator.Strategy, tier: Sender.Tier) throws {
        let clients = try strategy.clients(for: .mainnet, from: [
            Solana(), HeliusRPC(apiKey: "test-key"), Sender(tier: .premium),
        ])

        try #require(clients.count == 1)
        let sender = try #require(clients[0] as? Sender)
        #expect(sender.tier == tier)
    }

    /// Verifies a selected service cannot silently increase the requested priority fee.
    ///
    /// - Parameters:
    ///   - strategy: The service strategy selected for mainnet submission.
    ///   - requestedFee: A priority fee below the selected tier's requirement.
    ///   - minimumFee: The expected minimum total priority fee.
    @Test("Sender preparation rejects a priority fee below its requirement", arguments: [
        (TransactionCoordinator.Strategy.standard, UInt64(0), UInt64(1)),
        (.premium, UInt64(4_999), UInt64(5_000)),
    ])
    func senderRequiresReviewedPriorityFee(strategy: TransactionCoordinator.Strategy,
                                          requestedFee: UInt64, minimumFee: UInt64) async throws {
        let rpc = Solana()
        let transfer = try SystemProgram.transfer(from: Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), to: Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"), lamports: 1)
        let configuration = try Configuration(priorityFeeLamports: requestedFee,
                                               computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)

        let coordinator = try TransactionCoordinator(rpc: rpc,
            store: KeychainStore(service: "widgetsTests.Strategy"), rpcs: [rpc], strategy: strategy, configuration: configuration)

        await #expect(throws: Preparer.Failure.priorityFeeTooLow(minimumLamports: minimumFee)) {
            try await coordinator.simulate([transfer], using: Account(id: UUID(), address: transfer.accounts[0].address))
        }
    }

    /// Verifies unsupported Sender selection cannot silently submit through ordinary devnet RPCs.
    ///
    /// - Parameter strategy: The mainnet-only delivery strategy.
    @Test("Sender strategies reject devnet without falling back to ordinary RPCs", arguments: [
        TransactionCoordinator.Strategy.standard, .premium,
    ])
    func senderRejectsDevnet(strategy: TransactionCoordinator.Strategy) throws {
        let rpc = Solana(network: .devnet)
        #expect(throws: Submitter.Failure.noProviders) {
            try TransactionCoordinator(rpc: rpc, store: KeychainStore(service: "widgetsTests.Strategy"),
                                       rpcs: [rpc], strategy: strategy)
        }
    }
}
