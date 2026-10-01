import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies the coordinator's approval boundary independently of live RPC behavior.
struct ApprovalTests {
    /// Verifies approval cannot cross coordinator instances, even with the same provider and wallet.
    @Test("a review from another coordinator cannot unlock recovery")
    func anotherCoordinatorCannotApproveReview() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.preparation(fixture: fixture.preparation)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let first = try TransactionCoordinator(rpc: http.client, store: store, configuration: fixture.configuration)
        let second = try TransactionCoordinator(rpc: http.client, store: store, configuration: fixture.configuration)
        let review = try await first.simulate([fixture.transfer],
            using: fixture.account)

        await #expect(throws: ValidationError.invalidTransaction) { try await second.sign(review) }
        #expect(await store.reads.isEmpty)
    }

    /// Verifies invalid local authority selection fails before authentication.
    /// - Parameter selection: An empty, duplicated, or unrelated authority selection.
    @Test("invalid wallet selections cannot create an approvable review", arguments: ["empty", "duplicate", "unrelated"])
    func invalidWalletSelectionsAreRejected(_ selection: String) async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.preparation(fixture: fixture.preparation)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store, configuration: fixture.configuration)
        let payer = fixture.account
        let wallets = selection == "empty" ? [] : [payer, selection == "duplicate" ? payer
            : Account(id: UUID(), recoveryID: UUID(), address: fixture.transfer.accounts[1].address, index: 0)]
        let error: ValidationError = selection == "unrelated" ? .signerNotRequired : .invalidMessage

        await #expect(throws: error) { try await coordinator.simulate([fixture.transfer], using: wallets) }
        #expect(await store.reads.isEmpty)
    }

    /// Verifies broadcasting requires every unsigned authority before asking for biometrics.
    @Test("confirmation with a missing cosigner cannot unlock recovery")
    func missingCosignerPreventsAuthentication() async throws {
        let fixture = try ExternalFixture.preparation(hasPayerSignature: false)
        let http = try HTTPResponses.preparation(fixture: fixture)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store)
        let review = try await coordinator.simulate(fixture.transaction, using: SigningFixture().account)

        await #expect(throws: Submitter.Failure.missingSignatures) { try await coordinator.confirm(review) }
        #expect(await store.reads.isEmpty)
    }

    /// Verifies copies of one review cannot produce independently signed transactions.
    @Test("concurrent approval attempts unlock and sign a review only once")
    func concurrentApprovalSignsOnce() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: http.client, configuration: fixture.configuration,
            preparer: Preparer(rpc: (try HTTPResponses.preparation(fixture: fixture.preparation)).client),
            signer: Signer(rpc: http.client, store: store), submitter: Submitter(rpc: http.client), confirmer: Confirmer(rpc: http.client)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: fixture.account)
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
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: http.client, configuration: fixture.configuration,
            preparer: Preparer(rpc: (try HTTPResponses.preparation(fixture: fixture.preparation)).client),
            signer: Signer(rpc: http.client, store: store), submitter: Submitter(rpc: http.client, rpcs: []),
            confirmer: Confirmer(rpc: http.client)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: fixture.account)
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
