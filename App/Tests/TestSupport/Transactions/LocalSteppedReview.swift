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
    let followingTransactions: [Int]
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
        let following = followingTransactions[min(simulations.count, followingTransactions.endIndex - 1)]
        return ProposedTransaction(simulation: proposed.simulation, review: proposed.review, kind: proposed.kind,
                                   settling: proposed.settling, followingTransactions: following)
    }
}

@MainActor
struct LocalSteppedReview {
    let model: TransactionReviewModel<SteppedProposal>
    let recovery: SigningRecoveryStore
    let transactions: TransactionStore
    let sent: HTTPResponses
    let sockets: SocketSequence
    let clock = ManualClock()

    init(followingTransactions: [Int], failingSimulations: [Int: any Swift.Error] = [:],
         statuses: [GetSignatureStatuses.Response], height: UInt64 = 500,
         sockets: SocketSequence = SocketSequence()) throws {
        let payment = try LocalPaymentReview(statuses: statuses, height: height, sockets: sockets)
        recovery = payment.recovery
        transactions = payment.transactions
        sent = payment.sent
        self.sockets = payment.sockets
        model = try TransactionReviewModel(
            SteppedProposal(payment: payment.model.proposal, followingTransactions: followingTransactions,
                            failingSimulations: failingSimulations),
            from: payment.account, on: .devnet, transactions: transactions, clock: clock
        )
    }
}
