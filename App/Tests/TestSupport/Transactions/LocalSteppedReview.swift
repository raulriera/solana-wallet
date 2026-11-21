import Foundation
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct SteppedProposal: TransactionProposal {
    @MainActor
    final class Simulations {
        var count = 0
        var prepareCount = 0
        var onPrepare: (@MainActor () -> Void)?
    }

    typealias Review = PaymentProposal.Review
    typealias Error = SendError

    let payment: PaymentProposal
    let preliminaryCount: Int
    let reportedFollowing: Int?
    let failingSimulations: [Int: any Swift.Error]
    let simulations = Simulations()

    var refreshInterval: Duration { payment.refreshInterval }

    func prepare(from account: widgets.Account, on network: Network) async throws {
        simulations.prepareCount += 1
        simulations.onPrepare?()
    }

    func simulate(_ preparation: Void, with coordinator: any TransactionCoordinating, from account: widgets.Account)
        async throws -> ProposedTransaction<Review> {
        defer { simulations.count += 1 }
        if let error = failingSimulations[simulations.count] { throw error }
        let proposed = try await payment.simulate((), with: coordinator, from: account)
        let following = simulations.count < preliminaryCount
            ? reportedFollowing ?? preliminaryCount - simulations.count : 0
        return ProposedTransaction(simulation: proposed.simulation, review: proposed.review, kind: proposed.kind,
                                   settling: proposed.settling, followingTransactions: following)
    }
}

@MainActor
struct LocalSteppedReview {
    let model: TransactionReviewModel<SteppedProposal>
    let recovery: SigningRecoveryStore
    let transactions: TransactionStore
    let sent = HTTPResponses.sending()
    let sockets = SocketSequence()

    init(preliminaryCount: Int, reportedFollowing: Int? = nil, failingSimulations: [Int: any Swift.Error] = [:],
         statuses: [GetSignatureStatuses.Response], height: UInt64 = 500) throws {
        var fixture = try SigningFixture()
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: LocalPaymentReview.success)
        recovery = SigningRecoveryStore(recovery: fixture.recovery)
        let coordinator = try LocalTransactions(fixture: fixture, recovery: recovery, statuses: statuses, height: height,
                                                sockets: sockets, sent: sent).coordinator
        let payment = PaymentProposal(
            asset: .nativeSOL, sent: TokenAmount(lamports: 1_000_000_000), value: nil, currencyCode: "USD",
            recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: "Bruno"), warnings: [],
            recents: .inMemory())
        transactions = TransactionStore.inMemory { _ in coordinator }
        model = try TransactionReviewModel(
            SteppedProposal(payment: payment, preliminaryCount: preliminaryCount, reportedFollowing: reportedFollowing,
                            failingSimulations: failingSimulations),
            from: fixture.account, on: .devnet, transactions: transactions
        )
    }
}
