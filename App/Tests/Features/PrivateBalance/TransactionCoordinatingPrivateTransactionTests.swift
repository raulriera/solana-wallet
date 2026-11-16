import CryptoKit
import Foundation
import Privacy
import Testing
import Transactions
import Wallet
@testable import RPC
@testable import widgets

struct TransactionCoordinatingPrivateTransactionTests {
    private static let available: UInt64 = 20_000

    @Test
    func `Other transactions simulate once`() async throws {
        let fixture = try SigningFixture()
        let responses = try Self.responses(fees: [10_000])
        let prepared = PreparedPrivateTransaction(instructions: [fixture.transfer], account: fixture.account,
                                                  network: .devnet, effect: .deposit(1, of: .nativeSOL), registers: false,
                                                  authorities: [.account(fixture.account)])

        let (simulation, transaction) = try await Self.coordinator(fixture, responses).simulate(prepared)

        #expect(transaction.instructions == [fixture.transfer])
        #expect(simulation.fee == 10_000)
        #expect(try await responses.simulations() == 1)
    }

    @Test
    func `A sweep's network fee comes out of its deposit`() async throws {
        let fixture = try SigningFixture()
        let responses = try Self.responses(fees: [7_000])
        let prepared = try Self.sweep(fixture)

        let coordinator = try Self.coordinator(fixture, responses)

        let (simulation, transaction) = try await coordinator.simulate(prepared.withNetworkFee(3_000))

        guard case .redeem(let redemption) = transaction.effect else {
            Issue.record("Expected a redemption.")
            return
        }
        #expect(simulation.fee == 7_000)
        #expect(redemption.networkFee == 7_000)
        #expect(redemption.lamports == 13_001)
        #expect(transaction.instructions == (try prepared.withNetworkFee(7_000).instructions))
        #expect(try await responses.simulations() == 2)
    }

    @Test(arguments: [
        ([UInt64?.none], Redemption.FeeError.unknown),
        ([7_000, 8_000], .changed),
    ])
    func `A sweep with an unknown or changing fee is rejected`(fees: [UInt64?], error: Redemption.FeeError) async throws {
        let fixture = try SigningFixture()

        await #expect(throws: error) {
            try await Self.coordinator(fixture, Self.responses(fees: fees)).simulate(Self.sweep(fixture))
        }
    }

    @Test
    func `A fee above the sweep's lamports is underfunded`() async throws {
        let fixture = try SigningFixture()

        await #expect(throws: PrivateBalanceError.codeUnderfunded) {
            try await Self.coordinator(fixture, Self.responses(fees: [Self.available + 1])).simulate(Self.sweep(fixture))
        }
    }

    private static func coordinator(_ fixture: SigningFixture, _ responses: HTTPResponses) throws
        -> any TransactionCoordinating {
        try TransactionCoordinator.simulating(with: Preparer(rpc: responses.client),
                                              configuration: fixture.configuration)
    }

    private static func responses(fees: [UInt64?]) throws -> HTTPResponses {
        let fixture = try SigningFixture()
        return HTTPResponses([
            "getLatestBlockhash": [try HTTPResponses.json([
                "context": ["slot": fixture.blockhash.context.slot],
                "value": ["blockhash": fixture.blockhash.value.blockhash,
                          "lastValidBlockHeight": fixture.blockhash.value.lastValidBlockHeight],
            ])],
            "getFeeForMessage": try fees.map {
                try HTTPResponses.json(["context": ["slot": fixture.fee.context.slot], "value": $0 as Any? ?? NSNull()])
            },
            "simulateTransaction": [try HTTPResponses.simulation(fixture.simulation)],
        ])
    }

    private static func sweep(_ fixture: SigningFixture) throws -> PreparedPrivateTransaction {
        let source = try Address(fixture.oneTime.address)
        let redemption = try Redemption(instructions: [try MemoProgram.memo("sweep", signers: [source])], noteLamports: 1,
                                        availableLamports: available, source: source,
                                        recipient: fixture.oneTime.shieldedAccount.recipient, treeID: 1,
                                        takenBackIndex: nil)
        return PreparedPrivateTransaction(instructions: try redemption.transactionInstructions, account: fixture.account,
                                          network: .devnet, effect: .redeem(redemption), registers: false,
                                          authorities: [.oneTime(fixture.oneTime)])
    }
}
