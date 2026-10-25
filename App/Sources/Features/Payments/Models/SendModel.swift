import Foundation
import Observation
import RPC
import Transactions

/// One payment from the window's account to a recipient: the amount, its review, and how it settled.
///
/// Each step runs once per attempt in the sheet's task. Reviewing simulates the payment, which also builds the exact
/// transaction that the person approves; the review simulates it again while it shows, so it never expires. Sending
/// signs that transaction, which asks the person to authenticate, sends it, and watches it until it settles. A review
/// can be used once, so a cancelled authentication replaces it with a new simulation of the same payment. Errors before
/// anything is sent are typed; after sending, the payment keeps its signature, even when the watch stops.
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
    /// What the payment costs, once it's simulated.
    private(set) var review: Review?
    /// The sent payment's signature and network.
    private(set) var submission: Submission?
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
    private let transactions: any TransactionCoordinating
    private let portfolio: any PortfolioCoordinating

    /// Whether the payment is being signed, sent, and watched until it settles.
    var isSending: Bool { attempt?.work == .send }

    /// Whether a sent payment is being watched again.
    var isChecking: Bool { attempt?.work == .check }

    /// Whether the person can approve the review: it's simulated, unused, and no step is waiting or running.
    var canApprove: Bool { attempt == nil && simulation != nil && submission == nil }

    /// Starts a payment of the amount typed now; ``prepareReview()`` simulates it.
    /// - Parameters:
    ///   - payment: The keypad's payment, which a successful payment clears.
    ///   - recipient: Who the payment goes to.
    ///   - account: The window's account, which pays the amount and the fees.
    ///   - transactions: The window's network's transaction coordinator.
    ///   - portfolio: The window's portfolio, which reads the balances again after the payment lands.
    init(payment: PaymentModel, recipient: PaymentRecipient, account: Account,
         transactions: any TransactionCoordinating, portfolio: any PortfolioCoordinating) {
        amount = payment.amount
        self.recipient = recipient
        self.payment = payment
        self.account = account
        self.transactions = transactions
        self.portfolio = portfolio
    }

    /// Asks to simulate the payment for review, unless a step is waiting or running or it was sent.
    func prepareReview() {
        guard attempt == nil, submission == nil else { return }
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
        submission = nil
        outcome = nil
        start(.review)
    }

    /// Repeats the step that failed: watches a sent payment again, or simulates the payment again.
    func retry() {
        guard attempt == nil else { return }
        if submission != nil {
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
        guard attempt == nil, submission == nil, simulation != nil else { return }
        do {
            let simulated = try await simulate()
            // The person may have approved the review meanwhile.
            guard attempt == nil, submission == nil else { return }
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

    /// Signs and sends the reviewed payment, then watches it until it settles.
    ///
    /// A cancelled authentication uses up the review, so a new simulation of the same payment replaces it.
    private func send() async {
        guard let simulation else { return }
        let submission: Submission
        do {
            submission = try await transactions.submit(simulation)
        } catch let error as DeliveryError {
            // The payment was signed, and its delivery is unknown; the watch finds out whether it lands.
            self.submission = error.submission
            guard !Task.isCancelled else { return }
            await settle(error.submission)
            return
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await prepare()
            return
        } catch {
            self.simulation = nil
            self.error = .notSent
            return
        }
        self.submission = submission
        await settle(submission)
    }

    /// Watches the sent payment again.
    private func check() async {
        guard let submission else { return }
        await settle(submission)
    }

    /// Watches a sent payment until it settles, records the outcome, and reads the balances again once it landed.
    /// - Parameter submission: The sent payment's signature and network.
    private func settle(_ submission: Submission) async {
        let confirmation: Confirmation
        do {
            confirmation = try await transactions.confirm(submission)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .watchStopped
            return
        }
        switch confirmation.outcome {
        case .succeeded:
            outcome = .succeeded
            payment.clear()
        case .failed:
            outcome = .failed
        case .dropped:
            outcome = .dropped
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
        let simulation = try await transactions.transfer(amount.units, token: amount.token.mint, using: account,
                                                         to: recipient.address)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            throw execution.lacksFunds ? SendError.notEnoughSOL : SendError.preparationFailed
        }
        guard let fee = simulation.fee else { throw SendError.preparationFailed }
        let networkFee = simulation.tips.reduce(fee) { $0 + $1.tipLamports }
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
