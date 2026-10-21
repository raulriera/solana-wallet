import CryptoKit
import Foundation
import Privacy
@testable import RPC
import Testing
import Transactions
import Wallet
@testable import widgets

/// Verifies that a redeem or take-back's network fee is read with one simulation and charged to its trailing deposit
/// before the simulation that goes to approval, through the real coordinator and preparer with local responses.
struct TransactionCoordinatingPrivateTransactionTests {
    /// The lamports left for the network fee and the deposit of every fixture sweep.
    private static let available: UInt64 = 20_000

    /// A transaction without a sweep runs one simulation with its authorities and returns unchanged.
    @Test
    func `Other transactions simulate once`() async throws {
        let fixture = try SigningFixture()
        let responses = try Self.responses(fees: [10_000])
        let prepared = PreparedPrivateTransaction(instructions: [fixture.transfer], account: fixture.account,
                                                  network: .devnet, effect: .deposit(1), registers: false,
                                                  authorities: [.account(fixture.account)])

        let (simulation, transaction) = try await Self.coordinator(fixture, responses).simulate(prepared)

        #expect(transaction.instructions == [fixture.transfer])
        #expect(simulation.fee == 10_000)
        #expect(try await Self.simulations(of: responses) == 1)
    }

    /// A sweep reads the fee from a first simulation without a fee, then simulates and returns the transaction whose
    /// deposit is smaller by the fee.
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
        #expect(try await Self.simulations(of: responses) == 2)
    }

    /// A sweep whose fee is unknown, or whose charged transaction reports another fee, isn't returned for approval.
    /// - Parameters:
    ///   - fees: The fees of the two simulations.
    ///   - error: The expected rejection.
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

    /// A sweep whose fee exceeds the lamports left for it is underfunded.
    @Test
    func `A fee above the sweep's lamports is underfunded`() async throws {
        let fixture = try SigningFixture()

        await #expect(throws: PrivateBalanceError.codeUnderfunded) {
            try await Self.coordinator(fixture, Self.responses(fees: [Self.available + 1])).simulate(Self.sweep(fixture))
        }
    }

    /// Creates a coordinator whose preparation reads use local responses and that has no delivery route.
    /// - Parameters:
    ///   - fixture: The review observations and explicit resource requests.
    ///   - responses: The preparation responses.
    /// - Returns: The coordinator.
    /// - Throws: A fixture encoding error.
    private static func coordinator(_ fixture: SigningFixture, _ responses: HTTPResponses) throws
        -> any TransactionCoordinating {
        let signing = try HTTPResponses.signing()
        return TransactionCoordinator(
            rpc: signing.client, configuration: fixture.configuration, preparer: Preparer(rpc: responses.client),
            signer: Signer(validator: PreparationValidator(rpc: signing.client), store: UnavailableRecoveryStore()),
            submitter: Submitter(rpcs: []), confirmer: Confirmer(rpc: signing.client)
        )
    }

    /// Creates preparation responses whose fee reads return fees in order, the last one repeating.
    /// - Parameter fees: The network fees, or `nil` for an unknown fee.
    /// - Returns: The responses.
    /// - Throws: A JSON encoding error.
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

    /// Creates a sweep of the fixture's one-time account into its own shielded address, after a memo it signs.
    /// - Parameter fixture: The one-time account and the account whose balance changes.
    /// - Returns: The prepared sweep before its network fee.
    /// - Throws: A fixture error, which doesn't happen.
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

    /// Counts the simulations sent so far.
    /// - Parameter responses: The local responses that recorded the requests.
    /// - Returns: The number of `simulateTransaction` requests.
    /// - Throws: A test prerequisite error for a request without a method.
    private static func simulations(of responses: HTTPResponses) async throws -> Int {
        try await responses.requests.filter { try $0.rpcMethod == "simulateTransaction" }.count
    }
}
