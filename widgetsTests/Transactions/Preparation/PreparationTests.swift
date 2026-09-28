import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies preparation through the public service and actual V1 encoders.
struct PreparationTests {
    /// Verifies one message binds the displayed transfer, fee, expiry, and simulation.
    @Test("preparing a SOL transfer returns its exact message, total fee, and block-height expiry")
    func preparationReturnsMessageFeeAndExpiry() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let rpc = PreparationRPC(fixture: expected)
        let service: any TransactionPreparing = Preparer(rpc: rpc)

        let result = try await service.prepare(expectedSource.transfer, configuration: PreparationFixture.configuration())
        let resultSource = try PreparationFixture.source(result)

        #expect(resultSource.transfer.sender == expectedSource.transfer.sender)
        #expect(resultSource.transfer.recipient == expectedSource.transfer.recipient)
        #expect(resultSource.transfer.lamports == 1)
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

        let requests = await rpc.requests
        #expect(requests.count == 3)
        let blockhash = try #require(requests.first as? GetLatestBlockhash)
        let fee = try #require(requests.compactMap { $0 as? GetFeeForMessage }.first)
        let simulation = try #require(requests.compactMap { $0 as? SimulateTransaction }.first)
        #expect(blockhash.commitment == .confirmed)
        #expect(fee.commitment == .confirmed)
        #expect(simulation.commitment == .confirmed)
        #expect(fee.minContextSlot == 400)
        #expect(simulation.minContextSlot == 400)
        #expect(fee.message == expected.message)
        #expect(simulation.transaction == expected.message + Data(repeating: 0, count: 64))
        #expect(!simulation.verifiesSignatures)
        #expect(!simulation.replacesRecentBlockhash)
    }

    /// Verifies execution failures remain usable alongside the transfer's review data.
    @Test("insufficient funds preserve simulation diagnostics and transfer details")
    func insufficientFundsPreserveReviewData() async throws {
        let error = TransactionError(name: "InstructionError", details: .array([
            .integer(0), .object(["Custom": .integer(1)])
        ]))
        let expected = try PreparationFixture.preparation(error: error)
        let expectedSource = try PreparationFixture.source(expected)
        let service = Preparer(rpc: PreparationRPC(fixture: expected))

        let result = try await service.prepare(expectedSource.transfer, configuration: PreparationFixture.configuration())
        let resultSource = try PreparationFixture.source(result)

        #expect(result.simulation.value.error == error)
        #expect(result.simulation.value.logs == ["Transfer: insufficient lamports 0, need 1"])
        #expect(resultSource.transfer.recipient == expectedSource.transfer.recipient)
        #expect(resultSource.transfer.lamports == 1)
        #expect(result.fee.value == 10_000)
        #expect(resultSource.blockhash.value.lastValidBlockHeight == 550)
    }

    /// Verifies missing fee information isn't converted into a free-transfer estimate.
    @Test("an unavailable network fee remains unknown")
    func unavailableFeeRemainsUnknown() async throws {
        let expected = try PreparationFixture.preparation(fee: nil)
        let expectedSource = try PreparationFixture.source(expected)
        let service = Preparer(rpc: PreparationRPC(fixture: expected))

        let result = try await service.prepare(expectedSource.transfer, configuration: PreparationFixture.configuration())

        #expect(result.fee.value == nil)
        #expect(result.simulation.value == expected.simulation.value)
    }

    /// Verifies provider failures propagate without starting later work or retrying.
    @Test("a failed blockhash request stops preparation without retrying")
    func blockhashFailureStopsPreparation() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let failure = RPCError.http(statusCode: 429, retryAfter: "3")
        let rpc = PreparationRPC(fixture: expected, blockhashFailure: failure)
        let service = Preparer(rpc: rpc)

        await #expect(throws: failure) {
            try await service.prepare(expectedSource.transfer, configuration: PreparationFixture.configuration())
        }

        #expect(await rpc.requests.count == 1)
    }

    /// Verifies parent cancellation reaches the active child request and prevents a result.
    @Test("cancelling preparation cancels the pending simulation", .timeLimit(.minutes(1)))
    func cancellationReachesPendingSimulation() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let configuration = try PreparationFixture.configuration()
        let gate = Suspension()
        let rpc = PreparationRPC(fixture: expected, simulationGate: gate)
        let service = Preparer(rpc: rpc)
        let operation = Task { @concurrent in
            try await service.prepare(expectedSource.transfer, configuration: configuration)
        }
        defer { operation.cancel() }
        await gate.waitUntilStarted()

        operation.cancel()

        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await rpc.simulationWasCancelled)
    }
}
