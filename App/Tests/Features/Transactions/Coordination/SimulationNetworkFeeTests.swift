import Foundation
import Testing
import Transactions
@testable import RPC
@testable import widgets

struct SimulationNetworkFeeTests {
    @Test(arguments: [
        (SubmissionRequirements?.none, UInt64?(10_000), UInt64?(10_000)),
        (SenderSubmissionProvider(tier: .standard).submissionRequirements, 10_000, 15_000),
        (nil, nil, nil),
    ])
    func `The network fee adds any service tip to a known fee`(
        requirements: SubmissionRequirements?, fee: UInt64?, networkFee: UInt64?
    ) async throws {
        var fixture = try SigningFixture()
        let base = try PreparationFixture.preparation(fee: fee)
        fixture.fee = base.fee
        fixture.simulation = base.simulation
        let responses = try HTTPResponses.preparation(fixture: fixture.preparation)
        let rpc = try #require(responses.client(for: .solana, on: .mainnet))
        let coordinator = try TransactionCoordinator.simulating(with: Preparer(rpc: rpc, requirements: requirements),
                                                                configuration: fixture.configuration)

        let simulation = try await coordinator.transfer(1, of: .nativeSOL, using: fixture.account,
                                                        to: fixture.transfer.accounts[1].address)

        #expect(simulation.fee == fee)
        #expect(simulation.networkFee == networkFee)
    }
}
