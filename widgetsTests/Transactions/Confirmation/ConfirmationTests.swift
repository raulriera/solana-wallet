import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies observed execution separately from submission and unresolved status.
struct ConfirmationTests {
    private let submission = Submission(signature: ExternalFixture.signature, network: .devnet)

    /// Verifies missing and provisional statuses don't produce a successful confirmation.
    ///
    /// - Parameter commitment: A commitment level sufficient to complete observation.
    @Test("confirmation waits for confirmed or finalized execution", arguments: [Commitment.confirmed, .finalized])
    func confirmationWaitsForExecution(_ commitment: Commitment) async throws {
        let rpc = ConfirmationRPC(responses: [response(nil), response(status(.processed)),
                                              response(status(nil)), response(status(commitment))])
        let recovery = try SigningFixture().recovery
        let coordinator: any TransactionCoordinating = TransactionCoordinator(
            preparer: Preparer(rpc: rpc), signer: Signer(rpc: rpc, store: SigningRecoveryStore(recovery: recovery)),
            submitter: Submitter(rpc: rpc), confirmer: Confirmer(rpc: rpc, clock: pollingClock())
        )

        let confirmation = try await coordinator.confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405,
                                             commitment: commitment, outcome: .succeeded))
        let requests = await rpc.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.signatures == [submission.signature] && $0.searchesTransactionHistory })
    }

    /// Verifies an execution failure retains its details only once its fork is confirmed.
    @Test("confirmed execution failures retain instruction details")
    func executionFailuresRetainDetails() async throws {
        let error = TransactionError(name: "InstructionError", details: .array([.integer(1), .object(["Custom": .integer(6001)])]))
        let rpc = ConfirmationRPC(responses: [response(status(.processed, error: error)),
                                              response(status(.confirmed, error: error))])

        let confirmation = try await Confirmer(rpc: rpc, clock: pollingClock()).confirm(submission)

        #expect(confirmation.outcome == .failed(error))
        #expect(confirmation.slot == 405)
        #expect(confirmation.commitment == .confirmed)
        #expect(await rpc.requests.count == 2)
    }

    /// Verifies malformed positional or ledger observations cannot become confirmations.
    ///
    /// - Parameter kind: The malformed response shape or context.
    @Test("inconsistent status responses cannot confirm a transaction", arguments: ["empty", "extra status", "future slot"])
    func inconsistentResponsesAreRejected(_ kind: String) async {
        let values: [GetSignatureStatuses.Status?] = kind == "empty" ? [] : kind == "extra status"
            ? [status(.confirmed), nil] : [status(.confirmed)]
        let rpc = ConfirmationRPC(responses: [.init(context: Context(slot: kind == "future slot" ? 404 : 406), value: values)])

        await #expect(throws: Confirmer.Failure.invalidResponse) {
            try await Confirmer(rpc: rpc, clock: pollingClock()).confirm(submission)
        }

        #expect(await rpc.requests.count == 1)
    }

    /// Verifies observing another network never sends the signature to the provider.
    @Test("confirmation rejects another network before requesting status")
    func anotherNetworkIsRejected() async {
        let rpc = ConfirmationRPC(responses: [])

        await #expect(throws: Confirmer.Failure.networkMismatch) {
            try await Confirmer(rpc: rpc).confirm(Submission(signature: submission.signature, network: .mainnet))
        }

        #expect(await rpc.requests.isEmpty)
    }

    /// Verifies a failed lookup remains an observation error without an automatic retry.
    ///
    /// - Parameter failure: The transport or rate-limit error from the provider.
    @Test("status lookup failures preserve provider diagnostics without retrying", arguments: [
        RPCError.transport(.timedOut), .http(statusCode: 429, retryAfter: "3")
    ])
    func lookupFailuresDoNotRetry(_ failure: RPCError) async {
        let rpc = ConfirmationRPC(responses: [], failure: failure)

        await #expect(throws: failure) {
            try await Confirmer(rpc: rpc, clock: pollingClock()).confirm(submission)
        }

        #expect(await rpc.requests.count == 1)
    }

    /// Verifies the deadline cancels an in-flight request without fabricating an execution failure.
    @Test("confirmation timeout cancels pending status work and leaves the outcome unknown", .timeLimit(.minutes(1)))
    func timeoutCancelsPendingWork() async {
        let pending = Suspension()
        let rpc = ConfirmationRPC(responses: [response(status(.confirmed))], gate: pending)
        let clock = ControlledClock { duration in
            #expect(duration == .seconds(60))
            await pending.waitUntilStarted()
        }

        await #expect(throws: Confirmer.Failure.timedOut) {
            try await Confirmer(rpc: rpc, clock: clock).confirm(submission)
        }

        #expect(await rpc.wasCancelled)
        #expect(await rpc.requests.count == 1)
    }

    /// Verifies cancellation reaches either the pending RPC or the interval between queries.
    ///
    /// - Parameter duringRequest: Whether the task is cancelled during a request or a poll delay.
    @Test("cancelling confirmation stops requests and polling delays", .timeLimit(.minutes(1)), arguments: [true, false])
    func cancellationStopsObservation(duringRequest: Bool) async {
        let pending = Suspension()
        let deadline = Suspension()
        let rpc = ConfirmationRPC(responses: [response(duringRequest ? status(.confirmed) : nil)],
                                  gate: duringRequest ? pending : nil)
        let clock = ControlledClock { duration in
            if duration == .seconds(60) { await deadline.suspend() }
            else { await pending.suspend() }
        }
        let operation = Task { @concurrent in
            try await Confirmer(rpc: rpc, clock: clock).confirm(submission)
        }
        defer { operation.cancel() }
        await pending.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await rpc.requests.count == 1)
        #expect(await rpc.wasCancelled == duringRequest)
    }

    /// Creates a clock that advances polling immediately and holds the deadline until cancelled.
    ///
    /// - Returns: An independent clock with no wall-time delays.
    private func pollingClock() -> ControlledClock {
        let deadline = Suspension()
        return ControlledClock { duration in
            if duration == .seconds(60) { await deadline.suspend() }
            else { #expect(duration == .seconds(1)) }
        }
    }

    /// Creates an execution status without inferring finality from a missing confirmation count.
    ///
    /// - Parameters:
    ///   - commitment: The observed commitment, including an unavailable level.
    ///   - error: The execution failure, if any.
    /// - Returns: A status at slot 405 with its explicit commitment and outcome.
    private func status(_ commitment: Commitment?, error: TransactionError? = nil) -> GetSignatureStatuses.Status {
        .init(slot: 405, confirmations: nil, error: error, confirmationStatus: commitment)
    }

    /// Wraps a positional status in the provider's ledger context.
    ///
    /// - Parameter status: The observation, or `nil` for an unknown transaction.
    /// - Returns: A one-signature response observed at slot 406.
    private func response(_ status: GetSignatureStatuses.Status?) -> GetSignatureStatuses.Response {
        .init(context: Context(slot: 406), value: [status])
    }
}
