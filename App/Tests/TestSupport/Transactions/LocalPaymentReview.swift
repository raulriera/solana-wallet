import Foundation
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
struct LocalPaymentReview {
    static let networkFee: UInt64 = 10_000
    static let costs = PaymentProposal.Review(networkFee: networkFee, accountDeposit: nil, transferFee: nil)
    static let success = SimulateTransaction.Value(
        error: nil, logs: ["Program completed"], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: networkFee,
        replacementBlockhash: nil, preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
    )

    let model: TransactionReviewModel<PaymentProposal>
    let account: widgets.Account
    let transactions: TransactionStore
    let preparation: HTTPResponses
    let sockets: SocketSequence

    init(simulation: SimulateTransaction.Value = success, store: SigningRecoveryStore? = nil,
         statuses: [GetSignatureStatuses.Response] = [], height: UInt64 = 500,
         sockets: SocketSequence = SocketSequence(), sent: HTTPResponses = .sending()) throws {
        var fixture = try SigningFixture()
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: simulation)
        let local = try LocalTransactions(fixture: fixture, recovery: store, statuses: statuses, height: height,
                                          sockets: sockets, sent: sent)
        let coordinator = local.coordinator
        let transactions = TransactionStore.inMemory { _ in coordinator }
        let proposal = PaymentProposal(
            asset: .nativeSOL, sent: TokenAmount(lamports: 1_000_000_000), value: nil, currencyCode: "USD",
            recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: "Bruno"), warnings: [],
            recents: .inMemory())
        model = try TransactionReviewModel(proposal, from: fixture.account, on: .devnet, transactions: transactions)
        account = fixture.account
        self.transactions = transactions
        preparation = local.preparation
        self.sockets = sockets
    }
}
