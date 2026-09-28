import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies the coordinator's approval boundary independently of live RPC behavior.
struct ApprovalTests {
    /// Verifies copies of one review cannot produce independently signed transactions.
    @Test("concurrent approval attempts unlock and sign a review only once")
    func concurrentApprovalSignsOnce() async throws {
        let fixture = try SigningFixture()
        let rpc = SigningRPC()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: rpc, configuration: fixture.configuration,
            preparer: Preparer(rpc: PreparationRPC(fixture: fixture.preparation)),
            signer: Signer(rpc: rpc, store: store), submitter: Submitter(rpc: rpc), confirmer: Confirmer(rpc: rpc)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: Account(id: UUID(), address: fixture.transfer.accounts[0].address))
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await coordinator.sign(review)
                        return true
                    } catch TransactionCoordinator.Failure.reviewAlreadyUsed {
                        return false
                    }
                }
            }
            var results: [Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(results.filter { !$0 }.count == 1)
        #expect(await store.reads.count == 1)
    }

    /// Verifies failure after signing doesn't hide the identifier needed to reconcile delivery.
    @Test("a delivery failure retains the signed transaction identifier and original cause")
    func deliveryFailureRetainsReceipt() async throws {
        let fixture = try SigningFixture()
        let rpc = SigningRPC()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: rpc, configuration: fixture.configuration,
            preparer: Preparer(rpc: PreparationRPC(fixture: fixture.preparation)),
            signer: Signer(rpc: rpc, store: store), submitter: Submitter(rpc: rpc, rpcs: []),
            confirmer: Confirmer(rpc: rpc)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: Account(id: UUID(), address: fixture.transfer.accounts[0].address))
        await #expect {
            try await coordinator.confirm(review)
        } throws: { error in
            guard let failure = error as? TransactionCoordinator.DeliveryFailure else { return false }
            return failure.submission.network == .devnet && !failure.submission.signature.isEmpty
                && (failure.cause as? Submitter.Failure) == .noProviders
        }
        #expect(await store.reads.count == 1)
    }
}
