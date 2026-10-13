import Foundation
import RPC
import Testing
@testable import widgets

/// Verifies observed execution separately from submission and unresolved status.
struct ConfirmationTests {
    private let submission = Submission(signature: ExternalFixture.signature, network: .devnet, lastValidBlockHeight: 650)

    /// Verifies missing and provisional statuses don't produce a successful confirmation.
    ///
    /// - Parameter commitment: A commitment level sufficient to complete observation.
    @Test(arguments: [Commitment.confirmed, .finalized])
    func `Confirmation waits for confirmed or finalized execution`(_ commitment: Commitment) async throws {
        let http = try HTTPResponses.confirmation(responses: [response(nil), response(status(.processed)),
                                              response(status(nil)), response(status(commitment))])
        let confirmation = try await Confirmer(rpc: http.client, clock: pollingClock()).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405,
                                             commitment: commitment, outcome: .succeeded))
        let requests = await http.requests
        #expect(requests.count == 4)
        for request in requests {
            let parameters = try request.rpcParameters
            #expect(parameters[0] as? [String] == [submission.signature])
            #expect((parameters[1] as? [String: Bool])?["searchTransactionHistory"] == true)
        }
    }

    /// Verifies an execution failure retains its details only once its fork is confirmed.
    @Test
    func `Confirmed execution failures retain instruction details`() async throws {
        let error = TransactionError(name: "InstructionError", details: .array([.integer(1), .object(["Custom": .integer(6001)])]))
        let http = try HTTPResponses.confirmation(responses: [response(status(.processed, error: error)),
                                              response(status(.confirmed, error: error))])

        let confirmation = try await Confirmer(rpc: http.client, clock: pollingClock()).confirm(submission)

        #expect(confirmation.outcome == .failed(error))
        #expect(confirmation.slot == 405)
        #expect(confirmation.commitment == .confirmed)
        #expect(await http.requests.count == 2)
    }

    /// Verifies the coordinator observes a receipt through its confirmer alone.
    @Test
    func `A coordinator confirms a receipt without reading recovery or sending`() async throws {
        let http = try HTTPResponses.confirmation(responses: [response(status(.confirmed))])
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        let confirmation = try await coordinator(over: http, store: store).confirm(submission)

        #expect(confirmation == Confirmation(submission: submission, slot: 405, commitment: .confirmed, outcome: .succeeded))
        #expect(try await http.requests.map { try $0.rpcMethod } == ["getSignatureStatuses"])
        #expect(await store.reads.isEmpty)
    }

    /// Verifies a failed observation keeps the receipt and the provider's error without reading recovery.
    @Test
    func `A coordinator wraps observation errors with the receipt`() async throws {
        let rateLimit = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = try HTTPResponses.confirmation(responses: [], error: rateLimit)
        let store = SigningRecoveryStore(recovery: try SigningFixture().recovery)

        let error = try await #require(throws: DeliveryError.self) {
            try await coordinator(over: http, store: store).confirm(submission)
        }

        #expect(error.submission == submission)
        #expect((error.cause as? RPCError) == rateLimit)
        #expect(await http.requests.count == 1)
        #expect(await store.reads.isEmpty)
    }

    /// Verifies malformed positional or ledger observations cannot become confirmations.
    ///
    /// - Parameter kind: The malformed response shape or context.
    @Test(arguments: ["empty", "extra status", "future slot"])
    func `Inconsistent status responses cannot confirm a transaction`(_ kind: String) async throws {
        let values: [GetSignatureStatuses.Status?] = kind == "empty" ? [] : kind == "extra status"
            ? [status(.confirmed), nil] : [status(.confirmed)]
        let http = try HTTPResponses.confirmation(responses: [.init(context: Context(slot: kind == "future slot" ? 404 : 406), value: values)])

        await #expect(throws: ConfirmerError.invalidResponse) {
            try await Confirmer(rpc: http.client, clock: pollingClock()).confirm(submission)
        }

        #expect(await http.requests.count == 1)
    }

    /// Verifies observing another network never sends the signature to the provider.
    @Test
    func `Confirmation rejects another network before requesting status`() async throws {
        let http = try HTTPResponses.confirmation(responses: [])

        await #expect(throws: ConfirmerError.networkMismatch) {
            try await Confirmer(rpc: http.client).confirm(Submission(
                signature: submission.signature, network: .mainnet, lastValidBlockHeight: submission.lastValidBlockHeight
            ))
        }

        #expect(await http.requests.isEmpty)
    }

    /// Verifies a failed lookup remains an observation error without an automatic retry.
    ///
    /// - Parameter error: The transport or rate-limit error from the provider.
    @Test(arguments: [
        RPCError.transport(.timedOut), .http(statusCode: 429, retryAfter: "3")
    ])
    func `Status lookup failures preserve provider diagnostics without retrying`(_ error: RPCError) async throws {
        let http = try HTTPResponses.confirmation(responses: [], error: error)

        await #expect(throws: error) {
            try await Confirmer(rpc: http.client, clock: pollingClock()).confirm(submission)
        }

        #expect(await http.requests.count == 1)
    }

    /// Verifies the deadline cancels an in-flight request without fabricating an execution failure.
    @Test(.timeLimit(.minutes(1)))
    func `Confirmation timeout cancels pending status work and leaves the outcome unknown`() async throws {
        let pending = Suspension()
        let http = try HTTPResponses.confirmation(responses: [response(status(.confirmed))], gate: pending)
        let clock = ControlledClock { duration in
            #expect(duration == .seconds(60))
            await pending.waitUntilStarted()
        }

        await #expect(throws: ConfirmerError.timedOut) {
            try await Confirmer(rpc: http.client, clock: clock).confirm(submission)
        }

        #expect(await http.wasCancelled)
        #expect(await http.requests.count == 1)
    }

    /// Verifies cancellation reaches either the pending RPC or the interval between queries.
    ///
    /// - Parameter duringRequest: Whether the task is cancelled during a request or a poll delay.
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `Cancelling confirmation stops requests and polling delays`(duringRequest: Bool) async throws {
        let pending = Suspension()
        let deadline = Suspension()
        let http = try HTTPResponses.confirmation(responses: [response(duringRequest ? status(.confirmed) : nil)],
                                  gate: duringRequest ? pending : nil)
        let clock = ControlledClock { duration in
            if duration == .seconds(60) { await deadline.suspend() }
            else { await pending.suspend() }
        }
        let operation = Task { @concurrent in
            try await Confirmer(rpc: http.client, clock: clock).confirm(submission)
        }
        defer { operation.cancel() }
        await pending.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await http.requests.count == 1)
        #expect(await http.wasCancelled == duringRequest)
    }

    /// Creates a coordinator whose services share one HTTP fixture and recovery store.
    ///
    /// - Parameters:
    ///   - http: The fixture that serves every RPC request.
    ///   - store: The recovery store that records reads.
    /// - Returns: A coordinator that confirms with a polling clock.
    private func coordinator(over http: HTTPResponses, store: SigningRecoveryStore) -> any TransactionCoordinating {
        TransactionCoordinator(
            rpc: http.client, preparer: Preparer(rpc: http.client), signer: Signer(rpc: http.client, store: store),
            submitter: Submitter(rpc: http.client), confirmer: Confirmer(rpc: http.client, clock: pollingClock())
        )
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
