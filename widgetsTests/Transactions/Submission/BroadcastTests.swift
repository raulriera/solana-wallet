import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies provider selection and the lifetime of independently concurrent submissions.
struct BroadcastTests {
    /// Verifies both enabled peers receive identical bytes before either responds.
    @Test("the first acknowledgment returns while another enabled provider is still submitting", .timeLimit(.minutes(1)))
    func firstAcknowledgmentDoesNotWaitForSlowPeer() async throws {
        let fast = Suspension()
        let slow = Suspension()
        defer { fast.resume(); slow.resume() }
        let first = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature, gate: fast)
        let second = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature, gate: slow)
        let disabled = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature)
        let wrongNetwork = SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature, network: .mainnet)
        let providers = [Provider(rpc: first), Provider(rpc: second), Provider(rpc: disabled, isEnabled: false), Provider(rpc: wrongNetwork)]
        let checks = SigningRPC(fee: 15_000)
        let signed = try ExternalFixture.signedResult()
        let operation = Task { @concurrent in
            try await Submitter(rpc: checks, providers: providers).submit(signed)
        }
        defer { operation.cancel() }
        await fast.waitUntilStarted()
        await slow.waitUntilStarted()
        fast.resume()

        let receipt = try await operation.value
        defer { receipt.cancelPendingDeliveries() }

        #expect(receipt.signature == ExternalFixture.signature)
        for rpc in [first, second] {
            let requests = await rpc.requests
            #expect(requests.count == 1)
            let request = try #require(requests.first as? SendTransaction)
            #expect(request.transaction == signed.transaction.serializedRepresentation)
            #expect(request.minContextSlot == signed.preparation.minimumSlot)
        }
        #expect(await disabled.requests.isEmpty)
        #expect(await wrongNetwork.requests.isEmpty)
        #expect(await checks.requests.count == 2)
        slow.resume()
        let results = await receipt.deliveryResults()
        #expect(Set(results.map(\.providerID)) == Set(providers.prefix(2).map(\.id)))
        for result in results { if case .failure(let error) = result.result { Issue.record(error) } }
    }

    /// Verifies a rate limit cannot suppress another provider's acceptance or its diagnostic.
    @Test("one rate limited provider does not prevent another provider from accepting the transaction")
    func rateLimitDoesNotCancelAnotherProvider() async throws {
        let rejected = Provider(rpc: SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature,
                                                   failure: .http(statusCode: 429, retryAfter: "3")))
        let accepted = Provider(rpc: SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature))
        let receipt = try await Submitter(rpc: SigningRPC(fee: 15_000), providers: [rejected, accepted])
            .submit(ExternalFixture.signedResult())

        let results = await receipt.deliveryResults()

        #expect(receipt.signature == ExternalFixture.signature)
        #expect(results.count == 2)
        let rejection = try #require(results.first { $0.providerID == rejected.id })
        if case .failure(let error) = rejection.result {
            #expect(error as? RPCError == .http(statusCode: 429, retryAfter: "3"))
        } else {
            Issue.record("Rate limit was lost")
        }
    }

    /// Verifies local provider selection rejects an empty eligible set before any network work.
    @Test("no enabled provider on the transaction network prevents dispatch")
    func noEligibleProvidersPreventsDispatch() async throws {
        let checks = SigningRPC()
        let rpc = SubmissionRPC(checks: checks, acknowledgment: ExternalFixture.signature)
        let signed = try ExternalFixture.signedResult()

        await #expect(throws: Submitter.Failure.noEnabledProviders) {
            try await Submitter(rpc: checks, providers: [Provider(rpc: rpc, isEnabled: false)]).submit(signed)
        }

        #expect(await checks.requests.isEmpty)
        #expect(await rpc.requests.isEmpty)
    }

    /// Verifies parent cancellation reaches every pending route before any acknowledgment.
    @Test("cancelling before acknowledgment cancels every pending provider", .timeLimit(.minutes(1)))
    func cancellationReachesEveryProvider() async throws {
        let gates = [Suspension(), Suspension()]
        defer { for gate in gates { gate.resume() } }
        let providers = gates.map { Provider(rpc: SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature, gate: $0)) }
        let signed = try ExternalFixture.signedResult()
        let operation = Task { @concurrent in
            try await Submitter(rpc: SigningRPC(fee: 15_000), providers: providers).submit(signed)
        }
        defer { operation.cancel() }
        for gate in gates { await gate.waitUntilStarted() }

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        for gate in gates { await gate.waitUntilFinished() }
    }

    /// Verifies the last receipt releases the outstanding HTTP task without a task retain cycle.
    @Test("releasing the receipt cancels an unfinished provider", .timeLimit(.minutes(1)))
    func releasingReceiptCancelsPendingProvider() async throws {
        let gate = Suspension()
        defer { gate.resume() }
        let fast = Provider(rpc: SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature))
        let slow = Provider(rpc: SubmissionRPC(checks: SigningRPC(), acknowledgment: ExternalFixture.signature, gate: gate))
        var receipt: Submission? = try await Submitter(rpc: SigningRPC(fee: 15_000), providers: [fast, slow])
            .submit(ExternalFixture.signedResult())
        await gate.waitUntilStarted()
        #expect(receipt?.signature == ExternalFixture.signature)

        receipt = nil

        await gate.waitUntilFinished()
    }
}
