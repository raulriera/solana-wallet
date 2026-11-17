import Foundation
import RPC
import Testing
import Transactions
import Vault
import Wallet
@testable import widgets

struct StrategyTests {
    @Test(arguments: [
        (TransactionCoordinator.Strategy.none, SenderSubmissionProvider.Tier?.none),
        (.standard, .standard),
        (.premium, .premium),
    ])
    func `Each strategy submits through the provider or through Sender at its tier`(
        strategy: TransactionCoordinator.Strategy, tier: SenderSubmissionProvider.Tier?
    ) throws {
        let service = try strategy.service(on: .mainnet)

        #expect((service as? SenderSubmissionProvider)?.tier == tier)
        #expect((service == nil) == (tier == nil))
    }

    @Test(arguments: [
        (TransactionCoordinator.Strategy.standard, UInt64(0), UInt64(1)),
        (.premium, UInt64(4_999), UInt64(5_000)),
    ])
    func `Sender preparation rejects a priority fee below its requirement`(strategy: TransactionCoordinator.Strategy,
                                          requestedFee: UInt64, minimumFee: UInt64) async throws {
        let rpc = SolanaRPC(network: .mainnet)
        let transfer = try SystemProgram.transfer(from: Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"), to: Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"), lamports: 1)
        let configuration = try Configuration(priorityFeeLamports: requestedFee,
                                               computeUnitLimit: 20_000, loadedAccountsDataSizeLimit: 65_536)

        let coordinator = try TransactionCoordinator(rpc: rpc,
            store: KeychainStore(service: "widgetsTests.Strategy"), strategy: strategy, configuration: configuration)

        await #expect(throws: PreparerError.priorityFeeTooLow(minimumLamports: minimumFee)) {
            try await coordinator.simulate([transfer], using: Account(id: UUID(), recoveryID: UUID(), address: transfer.accounts[0].address, path: .solana))
        }
    }

    @Test(arguments: [
        TransactionCoordinator.Strategy.standard, .premium,
    ])
    func `Sender strategies reject devnet without falling back to the provider`(strategy: TransactionCoordinator.Strategy) throws {
        let rpc = SolanaRPC(network: .devnet)
        #expect(throws: TransactionCoordinatorError.unsupportedNetwork) {
            try TransactionCoordinator(rpc: rpc, store: KeychainStore(service: "widgetsTests.Strategy"),
                                       strategy: strategy)
        }
    }
}
