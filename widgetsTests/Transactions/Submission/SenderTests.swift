import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Explicitly authorized mainnet checks; Sender has no devnet delivery route.
@Suite(.serialized)
struct SenderTests {
    /// Verifies a selected Sender route lands the reviewed message within its quoted cost.
    ///
    /// Enable only after approval of the mainnet tips and fees. The retained wallet
    /// must already be funded; this test never requests funding or raises its bid.
    /// - Parameter strategy: The exclusive Sender tier selected for submission.
    @Test("Sender confirms a reviewed mainnet transaction at its quoted fee and tip",
          .enabled(if: ProcessInfo.processInfo.environment["VERIFY_MAINNET_SENDER"] == "APPROVED"),
          .timeLimit(.minutes(2)), arguments: [TransactionCoordinator.Strategy.standard, .premium])
    func senderConfirmsReviewedTransaction(_ strategy: TransactionCoordinator.Strategy) async throws {
        let key = try #require(ProcessInfo.processInfo.environment["HELIUS_API_KEY"])
        let rpc = HeliusRPC(apiKey: key, network: .mainnet)
        let account = Account(id: DevnetWallets.senderID,
            address: try await DevnetWallets.address(for: DevnetWallets.senderID))
        let balance = try await rpc.send(GetMultipleAccounts(addresses: [account.address.value]))
        let initial = try #require(balance.value[0]).lamports
        let coordinator = try TransactionCoordinator(rpc: rpc, store: DevnetWallets.store, strategy: strategy)
        let review = try await coordinator.simulate([MemoProgram.memo("widgets Sender verification")], using: account)
        let fee: UInt64 = strategy == .standard ? 5_001 : 10_000
        let tip: UInt64 = strategy == .standard ? 5_000 : 1_000_000
        try #require(review.fee == fee, "A changed quote requires another cost review")
        try #require(review.tips.map(\.tipLamports) == [tip])
        try #require(review.diagnostics.value.error == nil)
        let result = try await coordinator.confirm(review)
        try #require(result.outcome == .succeeded)
        let final = try await rpc.send(GetMultipleAccounts(addresses: [account.address.value], minContextSlot: result.slot))
        #expect(final.value[0]?.lamports == initial - fee - tip)
        print("Mainnet Sender \(strategy) confirmed: \(result.submission.signature); cost: \(fee + tip) lamports")
    }
}
