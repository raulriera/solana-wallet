import Foundation
@testable import RPC
import Testing
import Transactions
@testable import widgets

/// The review of a 1 SOL devnet payment from the signing fixture's account to its recipient, named Bruno, whose shared
/// transactions keep records in memory and whose real transaction coordinator answers from local responses and
/// sockets.
///
/// Every simulation reports a 10,000-lamport network fee.
@MainActor
struct LocalPaymentReview {
    /// The network fee of every simulation, in lamports.
    static let networkFee: UInt64 = 10_000
    /// The review of every successful simulation of a SOL payment.
    static let costs = PaymentProposal.Review(networkFee: networkFee, accountDeposit: nil)
    /// A successful simulation without balances.
    static let success = SimulateTransaction.Value(
        error: nil, logs: ["Program completed"], unitsConsumed: 150, loadedAccountsDataSize: 256, fee: networkFee,
        replacementBlockhash: nil, preBalances: nil, postBalances: nil, preTokenBalances: nil, postTokenBalances: nil
    )

    /// The review under test.
    let model: TransactionReviewModel<PaymentProposal>
    /// The account that pays.
    let account: widgets.Account
    /// The shared transactions, which send, record, and watch the payment.
    let transactions: TransactionStore
    /// The shared transactions' in-memory records.
    let records: StoredValue<[TransactionRecord]>
    /// The responses that answer the coordinator's preparation reads and simulations.
    let preparation: HTTPResponses
    /// The connections of the coordinator's watch.
    let sockets: SocketSequence

    /// Creates the review of a 1 SOL payment, before it's simulated.
    /// - Parameters:
    ///   - simulation: The simulated execution of every payment.
    ///   - store: The recovery storage that signing reads, or `nil` for the fixture recovery.
    ///   - statuses: The watch's status reads, in arrival order.
    ///   - height: The finalized block height of the watch's epoch reads.
    ///   - sockets: The watch's connections.
    ///   - sent: The responses that acknowledge each sent payment.
    /// - Throws: A fixture error.
    init(simulation: SimulateTransaction.Value = success, store: SigningRecoveryStore? = nil,
         statuses: [GetSignatureStatuses.Response] = [], height: UInt64 = 500,
         sockets: SocketSequence = SocketSequence(), sent: HTTPResponses = .sending()) throws {
        var fixture = try SigningFixture()
        fixture.simulation = SimulateTransaction.Response(context: Context(slot: 402), value: simulation)
        let local = try LocalTransactions(fixture: fixture, recovery: store, statuses: statuses, height: height,
                                          sockets: sockets, sent: sent)
        let coordinator = local.coordinator
        let records = StoredValue<[TransactionRecord]>()
        let transactions = TransactionStore.inMemory(records) { _ in coordinator }
        let sol = PaymentToken(mint: nil, symbol: "SOL", balance: 2, price: nil, decimals: 9)
        let proposal = PaymentProposal(
            amount: PaymentAmount(token: sol, quantity: 1, value: nil, currencyCode: "USD"),
            recipient: PaymentRecipient(address: fixture.transfer.accounts[1].address, name: "Bruno"), warnings: [])
        model = try TransactionReviewModel(proposal, from: fixture.account, on: .devnet, transactions: transactions)
        account = fixture.account
        self.transactions = transactions
        self.records = records
        preparation = local.preparation
        self.sockets = sockets
    }

    /// Creates a failed simulation without balances.
    /// - Parameter error: The execution error.
    /// - Returns: The execution.
    static func execution(error: TransactionError) -> SimulateTransaction.Value {
        SimulateTransaction.Value(error: error, logs: [], unitsConsumed: 150, loadedAccountsDataSize: 256,
                                  fee: networkFee, replacementBlockhash: nil, preBalances: nil, postBalances: nil,
                                  preTokenBalances: nil, postTokenBalances: nil)
    }

    /// Reviews the payment, as the sheet does when it opens.
    /// - Throws: A test failure when the review can't be approved.
    func review() async throws {
        model.prepareReview()
        await model.run(model.attempt)
        try #require(model.canApprove)
    }

    /// Counts the simulations sent so far.
    /// - Returns: The number of `simulateTransaction` requests.
    /// - Throws: A test prerequisite error for a request without a method.
    func simulations() async throws -> Int {
        try await preparation.requests.count { try $0.rpcMethod == "simulateTransaction" }
    }
}
