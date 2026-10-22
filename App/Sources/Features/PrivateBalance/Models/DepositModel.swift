import Foundation
import Observation
import RPC

/// One deposit of an account's public SOL into its own private balance: the amount, its review, and how it settled.
///
/// Each step runs once per attempt in the scene's task. Reviewing prepares and simulates the deposit; sending signs
/// it, which asks the person to authenticate, sends it, and watches it until it settles; checking watches a sent
/// deposit again after its watch stopped. A review can be used once, so a cancelled authentication replaces it with a
/// new simulation of the same deposit. Errors before anything is sent are typed; after sending, the outcome keeps the
/// signature, even when the watch stopped.
@MainActor
@Observable
final class DepositModel: Identifiable {
    /// What an attempt does.
    nonisolated enum Work: Hashable, Sendable {
        /// Prepares and simulates the deposit for review.
        case review
        /// Signs and sends the reviewed deposit, then watches it until it settles.
        case send
        /// Watches a sent deposit again after its watch stopped.
        case check
    }

    /// One run of a step, which the scene's task captures.
    nonisolated struct Attempt: Hashable, Sendable {
        /// Identifies the attempt, so a repeated step starts a new task.
        let id = UUID()
        /// What the attempt does.
        let work: Work
    }

    /// What the person approves: the SOL that moves and what it costs.
    nonisolated struct Review: Equatable, Sendable {
        /// The SOL that moves into the private balance, in lamports.
        let lamports: UInt64
        /// The network fee, in lamports.
        let networkFee: UInt64
        /// The one-time fee that registers the account with its first deposit, in lamports, or `nil` after it.
        let registrationFee: UInt64?
    }

    /// How a sent deposit settled.
    nonisolated enum Outcome: Equatable, Sendable {
        /// The deposit landed; its SOL is pending until the indexer reports it.
        case succeeded
        /// The deposit landed and failed; it paid its network fee and moved nothing.
        case failed
        /// The deposit can never land, so nothing left the public balance.
        case dropped
        /// The watch stopped before the deposit settled, such as after a rate limit; it can be checked again.
        case unconfirmed
    }

    /// The amount typed on the keypad, in SOL from the account's public balance.
    let payment: PaymentModel
    /// The review that the person approves, once the deposit is simulated.
    private(set) var review: Review?
    /// The sent deposit's signature and network.
    private(set) var submission: Submission?
    /// How the sent deposit settled.
    private(set) var outcome: Outcome?
    /// The account's private balance after the deposit settled, with the deposit pending when it succeeded.
    private(set) var status: PrivateBalanceStatus?
    /// The error of the last attempt.
    var error: PrivateBalanceError?
    /// The attempt that's waiting for the scene's task, or running.
    private(set) var attempt: Attempt?
    private var reviewed: (simulation: Simulation, transaction: PreparedPrivateTransaction)?
    private let account: Account
    private let network: Network
    private let balances: any PrivateBalancing
    private let transactions: any TransactionCoordinating

    /// Whether a step is waiting or running.
    var isWorking: Bool { attempt != nil }

    /// Whether the deposit is being signed and sent, and watched until it settles.
    var isSending: Bool { attempt?.work == .send }

    /// Whether a sent deposit is being watched again.
    var isChecking: Bool { attempt?.work == .check }

    /// Whether the person can approve the review: it's simulated, unused, and no step is waiting or running.
    var canApprove: Bool { attempt == nil && reviewed != nil && submission == nil }

    /// Whether the review shows; turning it off before anything is sent returns to the amount, whose next review
    /// simulates again.
    var isReviewing: Bool {
        get { review != nil }
        set {
            guard !newValue, attempt == nil, submission == nil else { return }
            review = nil
            reviewed = nil
        }
    }

    /// Starts an empty amount of SOL from the account's public balance.
    /// - Parameters:
    ///   - account: The account whose public SOL moves into its private balance.
    ///   - network: The window's network.
    ///   - publicLamports: The account's public SOL, in lamports.
    ///   - balances: The private balances of every account.
    ///   - transactions: The network's transaction coordinator.
    init(account: Account, network: Network, publicLamports: UInt64, balances: any PrivateBalancing,
         transactions: any TransactionCoordinating) {
        let sol = PaymentToken(symbol: "SOL", balance: Decimal(publicLamports) / Self.lamportsPerSOL, price: nil,
                               decimals: 9)
        // Without a price, the keypad types SOL and never shows the currency.
        payment = PaymentModel(tokens: [sol], currencyCode: "USD", source: .publicBalance)
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
    }

    /// Asks to review the typed amount, unless it can't be sent or a step is waiting or running.
    func prepareReview() {
        guard attempt == nil, payment.canSend else { return }
        start(.review)
    }

    /// Asks to sign and send the reviewed deposit, unless it can't be approved.
    func approve() {
        guard canApprove else { return }
        start(.send)
    }

    /// Asks to review the same amount again after the deposit was dropped; the last review shows until the new one
    /// replaces it, and can't be approved meanwhile.
    func tryAgain() {
        guard attempt == nil, outcome == .dropped else { return }
        reviewed = nil
        submission = nil
        outcome = nil
        start(.review)
    }

    /// Asks to watch the sent deposit again after its watch stopped.
    func checkAgain() {
        guard attempt == nil, outcome == .unconfirmed else { return }
        start(.check)
    }

    /// Runs a step once in the scene's SwiftUI-managed task.
    /// - Parameter attempt: The attempt that the scene's task captured.
    func run(_ attempt: Attempt?) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        switch attempt.work {
        case .review: await prepare()
        case .send: await send()
        case .check: await check()
        }
    }

    /// Simulates the reviewed deposit again, so its review never expires while the person reads it.
    ///
    /// Nothing changes on screen unless the fees do. Steps that are waiting or running, and settled deposits, skip it.
    func refreshReview() async {
        guard attempt == nil, submission == nil, let reviewed else { return }
        do {
            let simulated = try await simulate(reviewed.transaction)
            // The person may have left the review, or approved it, meanwhile.
            guard attempt == nil, submission == nil, review != nil else { return }
            show(simulated)
        } catch is CancellationError {
            // The review closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Starts a step for the scene's task.
    /// - Parameter work: What the step does.
    private func start(_ work: Work) {
        error = nil
        attempt = Attempt(work: work)
    }

    /// Prepares and simulates the typed amount, then shows its review.
    private func prepare() async {
        do {
            let lamports = NSDecimalNumber(decimal: payment.quantity * Self.lamportsPerSOL).uint64Value
            let prepared = try await balances.prepare(.deposit(lamports), from: account, on: network)
            show(try await simulate(prepared))
        } catch is CancellationError {
            // The sheet closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Signs and sends the reviewed deposit, then watches it until it settles.
    ///
    /// A cancelled authentication uses up the review, so a new simulation of the same deposit replaces it.
    private func send() async {
        guard let reviewed else { return }
        let submission: Submission
        do {
            submission = try await transactions.submit(reviewed.simulation)
        } catch let error as DeliveryError {
            self.submission = error.submission
            outcome = .unconfirmed
            return
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await replaceReview(of: reviewed.transaction)
            return
        } catch {
            self.error = Self.error(for: error)
            return
        }
        self.submission = submission
        await settle(submission, of: reviewed.transaction)
    }

    /// Watches the sent deposit again.
    private func check() async {
        guard let submission, let reviewed else { return }
        await settle(submission, of: reviewed.transaction)
    }

    /// Watches a sent deposit until it settles, records the outcome, and shows the private balance afterward.
    /// - Parameters:
    ///   - submission: The sent deposit's signature and network.
    ///   - transaction: The prepared deposit, which records the outcome.
    private func settle(_ submission: Submission, of transaction: PreparedPrivateTransaction) async {
        let confirmation: Confirmation
        do {
            confirmation = try await transactions.confirm(submission)
        } catch {
            guard !Task.isCancelled else { return }
            outcome = .unconfirmed
            return
        }
        // The deposit settled either way; without a record, the next read of the indexer still finds it.
        status = try? await balances.complete(transaction, with: confirmation)
        outcome = switch confirmation.outcome {
        case .succeeded: .succeeded
        case .failed: .failed
        case .dropped: .dropped
        }
    }

    /// Replaces a used review with a new simulation of the same deposit.
    /// - Parameter transaction: The prepared deposit.
    private func replaceReview(of transaction: PreparedPrivateTransaction) async {
        do {
            show(try await simulate(transaction))
        } catch is CancellationError {
            // The sheet closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Simulates a prepared deposit and reads what it costs.
    /// - Parameter prepared: The prepared deposit.
    /// - Returns: The simulation to approve, the transaction to record, and the review to show.
    /// - Throws: ``PrivateBalanceError/insufficientPublicBalance`` if the public SOL doesn't cover the deposit and its
    ///   fees, ``PrivateBalanceError/preparationFailed`` if the simulation fails otherwise or doesn't report the fees,
    ///   or the simulation's error.
    private func simulate(_ prepared: PreparedPrivateTransaction) async throws
        -> (simulation: Simulation, transaction: PreparedPrivateTransaction, review: Review) {
        guard case .deposit(let lamports) = prepared.effect else { throw PrivateBalanceError.preparationFailed }
        let (simulation, transaction) = try await transactions.simulate(prepared)
        let execution = simulation.diagnostics.value
        guard execution.error == nil else {
            throw execution.lacksFunds ? PrivateBalanceError.insufficientPublicBalance
                                       : PrivateBalanceError.preparationFailed
        }
        guard let fee = simulation.fee else { throw PrivateBalanceError.preparationFailed }
        let networkFee = simulation.tips.reduce(fee) { $0 + $1.tipLamports }
        var registrationFee: UInt64?
        if prepared.registers {
            // The payer's SOL pays the deposit, the network fee, and the registration's rent.
            guard let change = simulation.balanceChanges?.first(where: { $0.owner == account.address && $0.asset == .sol }),
                  change.before >= change.after, change.before - change.after >= lamports + networkFee else {
                throw PrivateBalanceError.preparationFailed
            }
            registrationFee = change.before - change.after - lamports - networkFee
        }
        return (simulation, transaction, Review(lamports: lamports, networkFee: networkFee,
                                                registrationFee: registrationFee))
    }

    /// Keeps a simulated deposit for approval and shows its review.
    /// - Parameter simulated: The simulation, the transaction to record, and the review.
    private func show(_ simulated: (simulation: Simulation, transaction: PreparedPrivateTransaction, review: Review)) {
        reviewed = (simulated.simulation, simulated.transaction)
        if review != simulated.review { review = simulated.review }
    }

    /// The error that an alert explains.
    /// - Parameter error: A preparation, simulation, or sending error.
    /// - Returns: The private-balance error itself, or ``PrivateBalanceError/preparationFailed``.
    private static func error(for error: any Error) -> PrivateBalanceError {
        error as? PrivateBalanceError ?? .preparationFailed
    }

    /// The lamports in one SOL.
    private static let lamportsPerSOL: Decimal = 1_000_000_000
}
