import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

struct SimulationNetworkFeeTests {
    @Test func `Without tips the network fee is the fee`() async throws {
        let fixture = try SigningFixture()
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)

        let simulation = try await Self.transfer(fixture, preparer: Preparer(rpc: responses.client))

        #expect(simulation.networkFee == 10_000)
    }

    @Test func `Service tips add to the network fee`() async throws {
        let fixture = try SigningFixture()
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)
        let rpc = try #require(responses.client(for: .solana, on: .mainnet))
        let requirements = Sender(tier: .standard).submissionRequirements

        let simulation = try await Self.transfer(fixture, preparer: Preparer(rpc: rpc, requirements: requirements))

        #expect(simulation.networkFee == 10_000 + requirements.tipLamports)
    }

    @Test func `An unknown fee leaves the network fee unknown`() async throws {
        var fixture = try SigningFixture()
        fixture.simulation = SimulateTransaction.Response(context: fixture.simulation.context, value: SimulateTransaction.Value(
            error: nil, logs: [], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: nil, replacementBlockhash: nil,
            preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
        ))
        fixture.fee = GetFeeForMessage.Response(context: fixture.fee.context, value: nil)
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)

        let simulation = try await Self.transfer(fixture, preparer: Preparer(rpc: responses.client))

        #expect(simulation.fee == nil)
        #expect(simulation.networkFee == nil)
    }

    private static func transfer(_ fixture: SigningFixture, preparer: Preparer) async throws -> Simulation {
        let signing = try HTTPResponses.signing()
        let coordinator = TransactionCoordinator(
            rpc: signing.client, configuration: fixture.configuration, preparer: preparer,
            signer: Signer(validator: PreparationValidator(rpc: signing.client), store: UnavailableRecoveryStore()),
            submitter: Submitter(rpc: signing.client), confirmer: Confirmer(rpc: signing.client)
        )
        return try await coordinator.transfer(1, using: fixture.account, to: fixture.transfer.accounts[1].address)
    }
}
