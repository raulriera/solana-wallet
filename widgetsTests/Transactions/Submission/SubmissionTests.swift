import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies typed app submission preserves the approved transaction and attempts one dispatch.
struct SubmissionTests {
    /// Verifies the caller prepares, signs, and submits typed values without serializing them.
    @Test("submitting a reviewed transaction returns its accepted signature and preserves every byte")
    func submissionPreservesSignedTransaction() async throws {
        let fixture = try ExternalFixture.preparation()
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)
        let rpc = SubmissionRPC(checks: SigningRPC(fee: 15_000, validities: [true]),
                                acknowledgment: ExternalFixture.signature)
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            preparer: Preparer(rpc: PreparationRPC(fixture: fixture)),
            signer: Signer(rpc: SigningRPC(fee: 15_000), store: store), submitter: Submitter(rpc: rpc), confirmer: Confirmer(rpc: rpc)
        )

        let preparation = try await coordinator.prepare(fixture.transaction, for: fixture.signer)
        let signed = try await coordinator.sign(preparation, for: UUID(), reason: "Approve transaction")
        let submission = try await coordinator.submit(signed)

        #expect(submission == Submission(signature: ExternalFixture.signature, network: .devnet))
        #expect(signed.signature == submission.signature)
        #expect(await store.reads.count == 1)
        let requests = await rpc.requests
        #expect(requests.count == 3)
        let sent = try #require(requests.last as? SendTransaction)
        #expect(sent.transaction == signed.transaction.serializedRepresentation)
        #expect(sent.preflightCommitment == .confirmed)
        #expect(sent.minContextSlot == 402)
        #expect(!sent.skipsPreflight)
        #expect(sent.maxRetries == 0)
    }

    /// Verifies a valid partial signature cannot be mistaken for a fully signed envelope.
    @Test("partially signed transactions never reach submission")
    func partialSignaturesPreventSubmission() async throws {
        let signed = try ExternalFixture.signedResult(hasPayerSignature: false)
        let rpc = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature)

        await #expect(throws: Submitter.Failure.missingSignatures) { try await Submitter(rpc: rpc).submit(signed) }

        #expect(!signed.isFullySigned)
        #expect(signed.signature == nil)
        #expect(await rpc.requests.isEmpty)
    }

    /// Verifies even a valid replacement cosigner signature cannot change the approved identifier.
    @Test("replacing an existing cosigner signature prevents submission")
    func replacingCosignerSignaturePreventsSubmission() async throws {
        let signed = try ExternalFixture.signedResult()
        let original = signed.transaction
        let replacement = try #require(Data(base64Encoded: ExternalFixture.alternatePayerSignature))
        try #require(replacement != original.signatures[0])
        let altered = Transaction(message: original.message, lifetimeSpecifier: original.lifetimeSpecifier,
                                  accounts: original.accounts, requests: original.requests,
                                  instructions: original.instructions, signatures: [replacement, original.signatures[1]])
        let input = SignedTransaction(preparation: signed.preparation, transaction: altered)
        let rpc = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature)

        await #expect(throws: Submitter.Failure.transactionMismatch) { try await Submitter(rpc: rpc).submit(input) }

        #expect(await rpc.requests.isEmpty)
    }

    /// Verifies signing doesn't bypass the shared lifetime check at later submission time.
    @Test("transactions that expire after signing are not broadcast")
    func expiredTransactionsAreNotBroadcast() async throws {
        let rpc = SubmissionRPC(checks: SigningRPC(fee: 15_000, validities: [false]),
                                acknowledgment: ExternalFixture.signature)
        let signed = try ExternalFixture.signedResult()

        await #expect(throws: PreparationValidator.Failure.expired) { try await Submitter(rpc: rpc).submit(signed) }

        let requests = await rpc.requests
        #expect(requests.count == 1)
        #expect(requests.first is IsBlockhashValid)
    }

    /// Verifies provider rejection and ambiguous transport failure retain their details without retries.
    ///
    /// - Parameter failure: The error returned by the single submission attempt.
    @Test("submission failures propagate without another broadcast attempt", arguments: [
        RPCError.transport(.timedOut), .http(statusCode: 429, retryAfter: "3"),
        .preflight(message: "Execution rejected", simulation: .init(
            error: TransactionError(name: "InsufficientFundsForFee", details: nil), logs: nil,
            unitsConsumed: nil, loadedAccountsDataSize: nil, fee: nil, replacementBlockhash: nil
        ))
    ])
    func submissionFailuresDoNotRetry(_ failure: RPCError) async throws {
        let rpc = SubmissionRPC(checks: SigningRPC(fee: 15_000, validities: [true]),
                                acknowledgment: ExternalFixture.signature, failure: failure)
        let other = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature,
                                  failure: .transport(.notConnectedToInternet))
        let providers = [Provider(rpc: rpc), Provider(rpc: other)]
        let signed = try ExternalFixture.signedResult()

        do {
            _ = try await Submitter(rpc: rpc, providers: providers).submit(signed)
            Issue.record("Submission unexpectedly received an acknowledgment")
        } catch let error as Broadcast.Failure {
            #expect(error.signature == ExternalFixture.signature)
            #expect(error.network == .devnet)
            let attempt = try #require(error.attempts.first { $0.providerID == providers[0].id })
            #expect(error.attempts.count == 2)
            if case .failure(let underlying) = attempt.result {
                #expect(underlying as? RPCError == failure)
            } else {
                Issue.record("Rejected request was reported as accepted")
            }
            let second = try #require(error.attempts.first { $0.providerID == providers[1].id })
            if case .failure(let underlying) = second.result {
                #expect(underlying as? RPCError == .transport(.notConnectedToInternet))
            } else {
                Issue.record("Offline provider was reported as accepted")
            }
        }

        #expect(await rpc.requests.filter { $0 is SendTransaction }.count == 1)
        #expect(await other.requests.count == 1)
        #expect(signed.signature == ExternalFixture.signature)
    }

    /// Verifies the provider can't substitute another transaction's identifier in the receipt.
    @Test("an unrelated acknowledgment retains the expected transaction signature")
    func unrelatedAcknowledgmentIsRejected() async throws {
        let rpc = SubmissionRPC(checks: SigningRPC(fee: 15_000, validities: [true]), acknowledgment: "another-signature")
        let signed = try ExternalFixture.signedResult()

        do {
            _ = try await Submitter(rpc: rpc).submit(signed)
            Issue.record("Submission accepted an unrelated signature")
        } catch let error as Broadcast.Failure {
            #expect(error.signature == ExternalFixture.signature)
            let attempt = try #require(error.attempts.first)
            if case .failure(let underlying) = attempt.result {
                #expect(underlying as? Submitter.Failure == .responseMismatch(expectedSignature: ExternalFixture.signature))
            } else {
                Issue.record("Unrelated signature was reported as accepted")
            }
        }

        #expect(await rpc.requests.filter { $0 is SendTransaction }.count == 1)
    }

    /// Verifies a dependency that returns after cancellation cannot report an accepted submission.
    @Test("cancelling submission discards a late acknowledgment without retrying", .timeLimit(.minutes(1)))
    func cancelledSubmissionDiscardsLateAcknowledgment() async throws {
        let gate = Suspension()
        let rpc = SubmissionRPC(checks: SigningRPC(fee: 15_000, validities: [true]),
                                acknowledgment: ExternalFixture.signature, gate: gate)
        let signed = try ExternalFixture.signedResult()
        let operation = Task { @concurrent in try await Submitter(rpc: rpc).submit(signed) }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await rpc.requests.filter { $0 is SendTransaction }.count == 1)
        #expect(signed.signature == ExternalFixture.signature)
    }
}
