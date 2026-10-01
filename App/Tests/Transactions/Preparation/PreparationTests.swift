import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies instruction preparation through the real client and actual V1 encoders.
struct PreparationTests {
    /// Verifies successful estimates cannot silently substitute missing or excessive resource usage.
    /// - Parameter usage: A malformed resource observation from the provider.
    @Test("resource estimates without valid compute and account usage cannot produce a review", arguments: [
        #""loadedAccountsDataSize":256"#, #""unitsConsumed":150"#,
        #""unitsConsumed":1400001,"loadedAccountsDataSize":256"#,
    ])
    func invalidResourceEstimatesPreventReview(_ usage: String) async throws {
        let fixture = try SigningFixture()
        let http = HTTPResponses([
            "getLatestBlockhash": [#"{"context":{"slot":400},"value":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":550}}"#],
            "simulateTransaction": [#"{"context":{"slot":401},"value":{"err":null,\#(usage)}}"#],
        ])
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store)

        await #expect(throws: Preparer.Failure.resourceUsageUnavailable) {
            try await coordinator.simulate([fixture.transfer], using: fixture.account)
        }
        #expect(await store.reads.isEmpty)
        #expect(try await http.requests.map { try $0.rpcMethod } == ["getLatestBlockhash", "simulateTransaction"])
    }

    /// Verifies estimates cannot change the lifetime or move behind the blockhash observation.
    /// - Parameter response: An inconsistent estimate returned as successful JSON-RPC.
    @Test("stale or blockhash-replacing estimates cannot produce a review", arguments: [
        #"{"context":{"slot":399},"value":{"err":null}}"#,
        #"{"context":{"slot":401},"value":{"err":null,"replacementBlockhash":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":600}}}"#,
    ])
    func inconsistentEstimatesPreventReview(_ response: String) async throws {
        let fixture = try SigningFixture()
        let http = HTTPResponses([
            "getLatestBlockhash": [#"{"context":{"slot":400},"value":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":550}}"#],
            "simulateTransaction": [response],
        ])
        await #expect(throws: Preparer.Failure.inconsistentResponse) {
            try await Preparer(rpc: http.client).prepare([fixture.transfer],
                payer: fixture.transfer.accounts[0].address, signer: fixture.transfer.accounts[0].address)
        }
    }

    /// Verifies one message binds the displayed transfer, fee, expiry, and simulation.
    @Test("preparing a SOL transfer returns its exact message, total fee, and block-height expiry")
    func preparationReturnsMessageFeeAndExpiry() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let http = try HTTPResponses.preparation(fixture: expected)
        let service: any TransactionPreparing = Preparer(rpc: http.client)

        let result = try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)
        let resultSource = try PreparationFixture.source(result)

        #expect(resultSource.instruction.accounts[0].address == expectedSource.instruction.accounts[0].address)
        #expect(resultSource.instruction.accounts[1].address == expectedSource.instruction.accounts[1].address)
        #expect(resultSource.instruction.data == expectedSource.instruction.data)
        #expect(resultSource.configuration.priorityFeeLamports == 5_000)
        #expect(resultSource.configuration.computeUnitLimit == 20_000)
        #expect(resultSource.configuration.loadedAccountsDataSizeLimit == 65_536)
        #expect(resultSource.configuration.heapSize == 65_536)
        #expect(result.network == .devnet)
        #expect(result.message == expected.message)
        #expect(resultSource.blockhash.value == expectedSource.blockhash.value)
        #expect(resultSource.blockhash.context.slot == 400)
        #expect(result.fee.value == 10_000) // Total already includes the 5,000-lamport priority fee.
        #expect(result.fee.context.slot == 401)
        #expect(result.simulation.value == expected.simulation.value)
        #expect(result.simulation.context.slot == 402)

        let requests = await http.requests
        #expect(requests.count == 3)
        let fee = try #require(requests.first { try $0.rpcMethod == "getFeeForMessage" }).rpcParameters
        let simulation = try #require(requests.first { try $0.rpcMethod == "simulateTransaction" }).rpcParameters
        #expect(fee[0] as? String == expected.message.base64EncodedString())
        #expect(simulation[0] as? String == (expected.message + Data(repeating: 0, count: 64)).base64EncodedString())
        let options = try #require(simulation[1] as? [String: Any])
        #expect(options["minContextSlot"] as? Int == 400)
        #expect(options["sigVerify"] as? Bool == false)
        #expect(options["replaceRecentBlockhash"] as? Bool == false)
    }

    /// Verifies execution failures remain usable alongside the transfer's review data.
    @Test("insufficient funds preserve simulation diagnostics and transfer details")
    func insufficientFundsPreserveReviewData() async throws {
        let error = TransactionError(name: "InstructionError", details: .array([
            .integer(0), .object(["Custom": .integer(1)])
        ]))
        let expected = try PreparationFixture.preparation(error: error)
        let expectedSource = try PreparationFixture.source(expected)
        let service = Preparer(rpc: (try HTTPResponses.preparation(fixture: expected)).client)

        let result = try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)
        let resultSource = try PreparationFixture.source(result)

        #expect(result.simulation.value.error == error)
        #expect(result.simulation.value.logs == ["Transfer: insufficient lamports 0, need 1"])
        #expect(resultSource.instruction.accounts[1].address == expectedSource.instruction.accounts[1].address)
        #expect(resultSource.instruction.data == expectedSource.instruction.data)
        #expect(result.fee.value == 10_000)
        #expect(resultSource.blockhash.value.lastValidBlockHeight == 550)
    }

    /// Verifies missing fee information isn't converted into a free-transfer estimate.
    @Test("an unavailable network fee remains unknown")
    func unavailableFeeRemainsUnknown() async throws {
        let expected = try PreparationFixture.preparation(fee: nil)
        let expectedSource = try PreparationFixture.source(expected)
        let service = Preparer(rpc: (try HTTPResponses.preparation(fixture: expected)).client)

        let result = try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)

        #expect(result.fee.value == nil)
        #expect(result.simulation.value == expected.simulation.value)
    }

    /// Verifies provider failures propagate without starting later work or retrying.
    @Test("a failed blockhash request stops preparation without retrying")
    func blockhashFailureStopsPreparation() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let failure = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = try HTTPResponses.preparation(fixture: expected, blockhashFailure: failure)
        let service = Preparer(rpc: http.client)

        await #expect(throws: failure) {
            try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)
        }

        #expect(await http.requests.count == 1)
    }

    /// Verifies parent cancellation reaches the active child request and prevents a result.
    @Test("cancelling preparation cancels the pending simulation", .timeLimit(.minutes(1)))
    func cancellationReachesPendingSimulation() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let configuration = try PreparationFixture.configuration()
        let gate = Suspension()
        let http = try HTTPResponses.preparation(fixture: expected, simulationGate: gate)
        let service = Preparer(rpc: http.client)
        let operation = Task { @concurrent in
            try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: configuration, minimumSlot: nil)
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await http.wasCancelled)
    }
}
