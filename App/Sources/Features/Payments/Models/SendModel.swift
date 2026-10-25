import Foundation
import Observation
import RPC
import Transactions

/// One payment from the window's account to a recipient: the amount, its review, and how it settled.
///
/// Each step runs once per attempt in the sheet's task. Reviewing simulates the payment, which also builds the exact
/// transaction that the person approves; the review simulates it again while it shows, so it never expires. Sending
/// hands that transaction to the shared transactions, which ask the person to authenticate, send it, record it, and
/// watch it until it settles, even after the sheet closes. A review can be used once, so a cancelled authentication
/// replaces it with a new simulation of the same payment. Errors before anything is sent are typed; after sending, the
/// payment keeps its record, even when the watch stops.
@MainActor
@Observable
final class SendModel: Identifiable {
    /// What an attempt does.
    nonisolated enum Work: Hashable, Sendable {
        /// Simulates the payment for review.
        case review
        /// Signs and sends the reviewed payment, then watches it until it settles.
        case send
        /// Watches a sent payment again after its watch stopped.
        case check
    }

    /// One run of a step, which the sheet's task captures.
    nonisolated struct Attempt: Hashable, Sendable {
        /// Identifies the attempt, so a repeated step starts a new task.
        let id = UUID()
        /// What the attempt does.
        let work: Work
    }

    /// What the person approves beyond the amount: what the payment costs.
    nonisolated struct Review: Equatable, Sendable {
        /// The network fee, with any service tip, in lamports.
        let networkFee: UInt64
        /// The rent that opens the recipient's account for the token, in lamports, or `nil` when it has one.
        let accountDeposit: UInt64?
    }

    /// How a sent payment settled.
    nonisolated enum Outcome: Equatable, Sendable {
        /// The payment landed and reached the recipient.
        case succeeded
        /// The payment landed and failed; it paid its network fee and moved nothing else.
        case failed
        /// The payment can never land, so nothing left the wallet.
        case dropped
    }

    /// The amount as typed when the person tapped Send.
    let amount: PaymentAmount
    /// Who the payment goes to.
    let recipient: PaymentRecipient
    /// What to check about the recipient, most serious first.
    let warnings: [RecipientWarning]
    /// What the payment costs, once it's simulated.
    private(set) var review: Review?
    /// The sent payment's record, as it was saved when the payment was sent.
    private(set) var record: TransactionRecord?
    /// How the sent payment settled.
    private(set) var outcome: Outcome?
    /// The error of the last attempt.
    var error: SendError?
    /// The attempt that's waiting for the sheet's task, or running.
    private(set) var attempt: Attempt?
    /// The simulation that the person approves, which can be signed once.
    private var simulation: Simulation?
    private let payment: PaymentModel
    private let account: Account
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore
    private let portfolio: any PortfolioCoordinating

    /// The sent payment's signature and network.
    var submission: Submission? { record?.submission }

    /// Whether the payment is being signed, sent, and watched until it settles.
    var isSending: Bool { attempt?.work == .send }

    /// Whether the person can approve the review: it's simulated, unused, and no step is waiting or running.
    var canApprove: Bool { attempt == nil && simulation != nil && record == nil }

    /// Starts a payment of the amount typed now; ``prepareReview()`` simulates it.
    /// - Parameters:
    ///   - payment: The keypad's payment, which a successful payment clears.
    ///   - recipient: Who the payment goes to.
    ///   - warnings: What to check about the recipient, most serious first.
    ///   - account: The window's account, which pays the amount and the fees.
    ///   - coordinator: The window's network's transaction coordinator, which simulates the payment.
    ///   - transactions: The shared transactions, which send, record, and watch the payment.
    ///   - portfolio: The window's portfolio, which reads the balances again after the payment lands.
    init(payment: PaymentModel, recipient: PaymentRecipient, warnings: [RecipientWarning], account: Account,
         coordinator: any TransactionCoordinating, transactions: TransactionStore,
         portfolio: any PortfolioCoordinating) {
        amount = payment.amount
        self.recipient = recipient
        self.warnings = warnings
        self.payment = payment
        self.account = account
        self.coordinator = coordinator
        self.transactions = transactions
        self.portfolio = portfolio
    }

    /// Asks to simulate the payment for review, unless a step is waiting or running or it was sent.
    func prepareReview() {
        guard attempt == nil, record == nil else { return }
        start(.review)
    }

    /// Asks to sign and send the reviewed payment, unless it can't be approved.
    func approve() {
        guard canApprove else { return }
        start(.send)
    }

    /// Asks to review the same payment again after it was dropped; the last review shows until the new one replaces
    /// it, and can't be approved meanwhile.
    func tryAgain() {
        guard attempt == nil, outcome == .dropped else { return }
        record = nil
        outcome = nil
        start(.review)
    }

    /// Repeats the step that failed: watches a sent payment again, or simulates the payment again.
    func retry() {
        guard attempt == nil else { return }
        if record != nil {
            guard outcome == nil else { return }
            start(.check)
        } else {
            start(.review)
        }
    }

    /// Runs a step once in the sheet's SwiftUI-managed task.
    /// - Parameter attempt: The attempt that the sheet's task captured.
    func run(_ attempt: Attempt?) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        switch attempt.work {
        case .review: await prepare()
        case .send: await send()
        case .check: await check()
        }
    }

    /// Simulates the reviewed payment again, so the review never expires while the person reads it.
    ///
    /// Nothing changes on screen unless the fees do. Steps that are waiting or running, and sent payments, skip it.
    func refreshReview() async {
        guard canApprove else { return }
        do {
            let simulated = try await simulate()
            // The person may have approved the review meanwhile.
            guard canApprove else { return }
            show(simulated)
        } catch is CancellationError {
            // The review closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Starts a step for the sheet's task.
    /// - Parameter work: What the step does.
    private func start(_ work: Work) {
        error = nil
        attempt = Attempt(work: work)
    }

    /// Simulates the payment and shows its review.
    private func prepare() async {
        simulation = nil
        do {
            show(try await simulate())
        } catch is CancellationError {
            // The sheet closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Sends the reviewed payment, then waits until it settles.
    ///
    /// A payment whose delivery is unknown is still recorded and watched, since it may land. A cancelled
    /// authentication uses up the review, so a new simulation of the same payment replaces it.
    private func send() async {
        guard let simulation else { return }
        let record: TransactionRecord
        do {
            record = try await transactions.send(
                simulation, as: .payment(recipient: recipient.address, mint: amount.token.mint, units: amount.units),
                from: account)
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await prepare()
            return
        } catch {
            self.simulation = nil
            self.error = .notSent
            return
        }
        self.record = record
        guard !Task.isCancelled else { return }
        await settle(record)
    }

    /// Waits again for the sent payment to settle.
    private func check() async {
        guard let record else { return }
        await settle(record)
    }

    /// Waits until a sent payment settles, shows the outcome, and reads the balances again once it landed.
    /// - Parameter record: The sent payment's record.
    private func settle(_ record: TransactionRecord) async {
        let status: TransactionRecord.Status
        do {
            status = try await transactions.watch(record.id, for: record.key)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .watchStopped
            return
        }
        switch status {
        case .succeeded:
            outcome = .succeeded
            payment.clear()
        case .failed:
            outcome = .failed
        case .dropped:
            outcome = .dropped
            return
        case .pending:
            // A watch returns only once the payment settled.
            return
        }
        // A landed payment changed the balances, failed or not, since it paid its fee.
        await portfolio.refresh()
    }

    /// Simulates the payment and reads what it costs.
    /// - Returns: The simulation to approve and the review to show.
    /// - Throws: ``SendError/notEnoughSOL`` if the account's SOL doesn't cover the payment and its fees,
    ///   ``SendError/preparationFailed`` if the simulation fails otherwise or doesn't report the fee, or the
    ///   simulation's error.
    private func simulate() async throws -> (simulation: Simulation, review: Review) {
        let simulation = try await coordinator.transfer(amount.units, token: amount.token.mint, using: account,
                                                         to: recipient.address)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            throw execution.lacksFunds ? SendError.notEnoughSOL : SendError.preparationFailed
        }
        guard let networkFee = simulation.networkFee else { throw SendError.preparationFailed }
        let accountDeposit = simulation.destinationAccountRent.flatMap { $0 > 0 ? $0 : nil }
        return (simulation, Review(networkFee: networkFee, accountDeposit: accountDeposit))
    }

    /// Keeps a simulated payment for approval and shows its review.
    /// - Parameter simulated: The simulation and the review.
    private func show(_ simulated: (simulation: Simulation, review: Review)) {
        simulation = simulated.simulation
        if review != simulated.review { review = simulated.review }
    }

    /// The error that an alert explains.
    /// - Parameter error: A preparation or simulation error.
    /// - Returns: The send error itself, or ``SendError/preparationFailed``.
    private static func error(for error: any Error) -> SendError {
        error as? SendError ?? .preparationFailed
    }
}
