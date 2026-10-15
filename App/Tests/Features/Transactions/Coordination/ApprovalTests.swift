import Foundation
import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies the coordinator's approval boundary independently of live RPC behavior.
struct ApprovalTests {
    /// Verifies approval cannot cross coordinator instances, even with the same provider and wallet.
    @Test
    func `A review from another coordinator cannot unlock recovery`() async throws {
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
    @Test(arguments: ["empty", "duplicate", "unrelated"])
    func `Invalid wallet selections cannot create an approvable review`(_ selection: String) async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.preparation(fixture: fixture.preparation)
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store, configuration: fixture.configuration)
        let payer = fixture.account
        let wallets = selection == "empty" ? [] : [payer, selection == "duplicate" ? payer
            : Account(id: UUID(), recoveryID: UUID(), address: fixture.transfer.accounts[1].address, path: .solana)]
        let error: ValidationError = selection == "unrelated" ? .signerNotRequired : .invalidMessage

        await #expect(throws: error) { try await coordinator.simulate([fixture.transfer], using: wallets) }
        #expect(await store.reads.isEmpty)
    }

    /// Verifies broadcasting requires every unsigned authority before asking for biometrics.
    @Test
    func `Submitting with a missing cosigner cannot unlock recovery`() async throws {
        let fixture = try ExternalFixture.preparation(hasPayerSignature: false)
        let http = try HTTPResponses.preparation(fixture: fixture)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store)
        let review = try await coordinator.simulate(fixture.transaction, using: SigningFixture().account)

        await #expect(throws: SubmitterError.missingSignatures) { try await coordinator.submit(review) }
        #expect(await store.reads.isEmpty)
    }

    /// Verifies copies of one review cannot produce independently signed transactions.
    @Test
    func `Concurrent approval attempts unlock and sign a review only once`() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: http.client, configuration: fixture.configuration,
            preparer: Preparer(rpc: (try HTTPResponses.preparation(fixture: fixture.preparation)).client),
            signer: Signer(rpc: http.client, store: store), submitter: Submitter(rpcs: [http.client]), confirmer: Confirmer(rpc: http.client)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: fixture.account)
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await coordinator.sign(review)
                        return true
                    } catch TransactionCoordinatorError.reviewAlreadyUsed {
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

    /// Verifies failure after signing doesn't hide the receipt needed to reconcile delivery.
    @Test
    func `A delivery failure retains the signed transaction receipt, its expiry, and the original cause`() async throws {
        let fixture = try SigningFixture()
        let http = try HTTPResponses.signing()
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            rpc: http.client, configuration: fixture.configuration,
            preparer: Preparer(rpc: (try HTTPResponses.preparation(fixture: fixture.preparation)).client),
            signer: Signer(rpc: http.client, store: store), submitter: Submitter(rpcs: []),
            confirmer: Confirmer(rpc: http.client)
        )
        let review = try await coordinator.simulate([fixture.transfer],
            using: fixture.account)
        let error = try await #require(throws: DeliveryError.self) {
            try await coordinator.submit(review)
        }
        #expect(error.submission.network == .devnet)
        #expect(error.submission.signature.isEmpty == false)
        #expect(error.submission.lastValidBlockHeight == 550)
        #expect((error.cause as? SubmitterError) == .noProviders)
        #expect(await store.reads.count == 1)
    }
}
