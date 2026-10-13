import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Explicitly authorized mainnet checks; Sender has no devnet delivery route.
/// Cases run serially because both spend from the configured test wallet's sender.
@Suite(.serialized)
struct SenderTests {
    /// Verifies a selected Sender route lands the reviewed message within its quoted cost.
    ///
    /// Enable only after approval of the mainnet tips and fees. The configured test wallet's sender
    /// must already be funded; this test never requests funding or raises its bid.
    /// - Parameter strategy: The exclusive Sender tier selected for submission.
    /// - Throws: A credential, recovery, provider, or spending-limit prerequisite error.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VERIFY_MAINNET_SENDER"] == "APPROVED"),
          .timeLimit(.minutes(2)), arguments: [TransactionCoordinator.Strategy.standard, .premium])
    func `Sender confirms a reviewed mainnet transaction at its quoted fee and tip`(_ strategy: TransactionCoordinator.Strategy) async throws {
        let rpc = try MainnetClients.client()
        let wallets = try await DevnetWallets.configured()
        let account = wallets.sender
        let balance = try await rpc.send(GetMultipleAccounts(addresses: [account.address.value]))
        try #require(balance.value.count == 1)
        let initial = try #require(balance.value[0]).lamports
        let coordinator = try TransactionCoordinator(rpc: rpc, store: SigningRecoveryStore(recovery: wallets.recovery),
                                                     strategy: strategy)
        let review = try await coordinator.simulate([MemoProgram.memo("widgets Sender verification")], using: account)
        let fee: UInt64 = strategy == .standard ? 5_001 : 10_000
        let tip: UInt64 = strategy == .standard ? 5_000 : 1_000_000
        try #require(review.fee == fee, "A changed quote requires another cost review")
        try #require(review.tips.map(\.tipLamports) == [tip])
        try #require(review.diagnostics.value.error == nil)
        try #require(initial >= fee + tip, "The configured test wallet's mainnet sender must already cover the approved cost")
        let submission = try await coordinator.submit(review)
        let result = try await coordinator.confirm(submission)
        try #require(result.outcome == .succeeded)
        let final = try await rpc.send(GetMultipleAccounts(addresses: [account.address.value], minContextSlot: result.slot))
        try #require(final.value.count == 1)
        #expect(final.value[0]?.lamports == initial - fee - tip)
        print("Mainnet Sender \(strategy) confirmed: \(result.submission.signature); cost: \(fee + tip) lamports")
    }
}
