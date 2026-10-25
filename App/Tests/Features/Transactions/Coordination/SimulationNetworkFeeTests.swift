import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// Verifies a review's network fee, which adds the service tips that the transaction pays to its fee, through the real
/// coordinator with local responses.
///
/// Every fixture simulation reports a 10,000-lamport fee.
struct SimulationNetworkFeeTests {
    /// A transfer without service tips costs its fee.
    /// - Throws: A fixture error.
    @Test func `Without tips the network fee is the fee`() async throws {
        let fixture = try SigningFixture()
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)

        let simulation = try await Self.transfer(fixture, preparer: Preparer(rpc: responses.client))

        #expect(simulation.networkFee == 10_000)
    }

    /// A transfer sent through Sender also pays its tip.
    /// - Throws: A fixture error.
    @Test func `Service tips add to the network fee`() async throws {
        let fixture = try SigningFixture()
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)
        let rpc = try #require(responses.client(for: .solana, on: .mainnet))
        let sender = Sender(tier: .standard)
        let tip = try #require(sender.submissionRequirements).tipLamports

        let simulation = try await Self.transfer(fixture, preparer: Preparer(rpc: rpc, rpcs: [sender]))

        #expect(simulation.networkFee == 10_000 + tip)
    }

    /// A fee that the provider couldn't tell stays unknown, whatever the tips.
    /// - Throws: A fixture error.
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

    /// Simulates a 1-lamport SOL transfer from the fixture account.
    /// - Parameters:
    ///   - fixture: The account, recipient, and explicit resource requests.
    ///   - preparer: The preparer whose responses and tips the simulation uses.
    /// - Returns: The review.
    /// - Throws: A fixture or preparation error.
    private static func transfer(_ fixture: SigningFixture, preparer: Preparer) async throws -> Simulation {
        let signing = try HTTPResponses.signing()
        let coordinator = TransactionCoordinator(
            rpc: signing.client, configuration: fixture.configuration, preparer: preparer,
            signer: Signer(validator: PreparationValidator(rpc: signing.client), store: UnavailableRecoveryStore()),
            submitter: Submitter(rpcs: []), confirmer: Confirmer(rpc: signing.client)
        )
        return try await coordinator.transfer(1, using: fixture.account, to: fixture.transfer.accounts[1].address)
    }
}
