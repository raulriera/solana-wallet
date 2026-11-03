import Foundation
import RPC
import Testing
import Transactions
import Wallet
import Vault
@testable import widgets

struct StrategyTests {
    @Test
    func `None submits through the provider`() throws {
        #expect(try TransactionCoordinator.Strategy.none.service(on: .mainnet) == nil)
    }

    @Test(arguments: [
        (TransactionCoordinator.Strategy.standard, Sender.Tier.standard),
        (.premium, .premium),
    ])
    func `Sender strategies replace the provider with one selected tier`(strategy: TransactionCoordinator.Strategy, tier: Sender.Tier) throws {
        let sender = try #require(strategy.service(on: .mainnet) as? Sender)

        #expect(sender.tier == tier)
    }

    @Test(arguments: [
        (TransactionCoordinator.Strategy.standard, UInt64(0), UInt64(1)),
        (.premium, UInt64(4_999), UInt64(5_000)),
    ])
    func `Sender preparation rejects a priority fee below its requirement`(strategy: TransactionCoordinator.Strategy,
                                          requestedFee: UInt64, minimumFee: UInt64) async throws {
        let rpc = Solana()
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
        let rpc = Solana(network: .devnet)
        #expect(throws: TransactionCoordinatorError.unsupportedNetwork) {
            try TransactionCoordinator(rpc: rpc, store: KeychainStore(service: "widgetsTests.Strategy"),
                                       strategy: strategy)
        }
    }
}
