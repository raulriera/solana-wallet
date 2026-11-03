import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

struct PreparationTests {
    @Test(arguments: [
        #""loadedAccountsDataSize":256"#, #""unitsConsumed":150"#,
        #""unitsConsumed":1400001,"loadedAccountsDataSize":256"#,
    ])
    func `Resource estimates without valid compute and account usage cannot produce a review`(_ usage: String) async throws {
        let fixture = try SigningFixture()
        let http = HTTPResponses([
            "getLatestBlockhash": [#"{"context":{"slot":400},"value":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":550}}"#],
            "simulateTransaction": [#"{"context":{"slot":401},"value":{"err":null,\#(usage)}}"#],
        ])
        let store = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try TransactionCoordinator(rpc: http.client, store: store)

        await #expect(throws: PreparerError.resourceUsageUnavailable) {
            try await coordinator.simulate([fixture.transfer], using: fixture.account)
        }
        #expect(await store.reads.isEmpty)
        #expect(try await http.requests.map { try $0.rpcMethod } == ["getLatestBlockhash", "simulateTransaction"])
    }

    @Test(arguments: [
        #"{"context":{"slot":399},"value":{"err":null}}"#,
        #"{"context":{"slot":401},"value":{"err":null,"replacementBlockhash":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":600}}}"#,
    ])
    func `Stale or blockhash-replacing estimates cannot produce a review`(_ response: String) async throws {
        let fixture = try SigningFixture()
        let http = HTTPResponses([
            "getLatestBlockhash": [#"{"context":{"slot":400},"value":{"blockhash":"11111111111111111111111111111111","lastValidBlockHeight":550}}"#],
            "simulateTransaction": [response],
        ])
        await #expect(throws: PreparerError.inconsistentResponse) {
            try await Preparer(rpc: http.client).prepare([fixture.transfer],
                payer: fixture.transfer.accounts[0].address, signer: fixture.transfer.accounts[0].address)
        }
    }

    @Test
    func `Preparing a SOL transfer returns its exact message, total fee, and block-height expiry`() async throws {
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
        #expect(result.fee.value == 10_000)
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
        for request in requests {
            #expect(try (request.rpcParameters.last as? [String: Any])?["commitment"] as? String == "finalized")
        }
    }

    @Test
    func `Sender tips precede the caller's instructions`() async throws {
        let fixture = try PreparationFixture.preparation()
        let transfer = try PreparationFixture.source(fixture).instruction
        let payer = transfer.accounts[0].address
        let memo = try MemoProgram.memo("widgets tip order", signers: [payer])
        let requirements = try #require(Sender(tier: .standard).submissionRequirements)
        let tip = try SystemProgram.transfer(from: payer, to: Address(requirements.tipRecipient),
                                             lamports: requirements.tipLamports)
        let http = try HTTPResponses.preparation(fixture: fixture)
        let rpc = try #require(http.client(for: .solana, on: .mainnet))

        let result = try await Preparer(rpc: rpc, requirements: requirements).prepare([memo, transfer], payer: payer, signer: payer,
            configuration: PreparationFixture.configuration())

        let expected = [tip, memo, transfer]
        guard case .local(let instructions, _, _, _) = result.source else {
            Issue.record("Expected local construction details")
            return
        }
        #expect(instructions == expected)
        let accounts = result.transaction.accounts.map(\.address)
        #expect(result.transaction.instructions.map { accounts[$0.programIndex] } == expected.map(\.program))
        #expect(result.transaction.instructions.map { $0.accountIndices.map { accounts[$0] } }
                == expected.map { $0.accounts.map(\.address) })
        #expect(result.transaction.instructions.map(\.data) == expected.map(\.data))
    }

    @Test
    func `Insufficient funds preserve simulation diagnostics and transfer details`() async throws {
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

    @Test
    func `An unavailable network fee remains unknown`() async throws {
        let expected = try PreparationFixture.preparation(fee: nil)
        let expectedSource = try PreparationFixture.source(expected)
        let service = Preparer(rpc: (try HTTPResponses.preparation(fixture: expected)).client)

        let result = try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)

        #expect(result.fee.value == nil)
        #expect(result.simulation.value == expected.simulation.value)
    }

    @Test
    func `A failed blockhash request stops preparation without retrying`() async throws {
        let expected = try PreparationFixture.preparation()
        let expectedSource = try PreparationFixture.source(expected)
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        let http = try HTTPResponses.preparation(fixture: expected, blockhashError: error)
        let service = Preparer(rpc: http.client)

        await #expect(throws: error) {
            try await service.prepare([expectedSource.instruction], payer: expectedSource.payer, signer: expected.signer, configuration: PreparationFixture.configuration(), minimumSlot: nil)
        }

        #expect(await http.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling preparation cancels the pending simulation`() async throws {
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
