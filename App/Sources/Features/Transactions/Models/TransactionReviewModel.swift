import Foundation
import Observation
import RPC
import Transactions

/// One review of a proposed transaction: what it shows, its approval, and how the sent transaction settled.
///
/// Each step runs once per attempt in the review's task. Reviewing prepares and simulates the transaction, which builds
/// the exact transaction that the person approves; the review simulates it again while it shows, so it never expires.
/// Approving hands it to the shared transactions, which ask the person to authenticate, send it, record it, and watch it
/// until it settles, even after the review closes. The sent transaction's status comes from its record in the shared
/// transactions, so a watch that stops leaves the review waiting until a later watch settles the record. A simulation
/// can be signed once, so a cancelled authentication replaces it with a new simulation of the same preparation.
@MainActor
@Observable
final class TransactionReviewModel<Proposal: TransactionProposal>: Identifiable {
    /// What an attempt does.
    nonisolated enum Work: Hashable, Sendable {
        /// Prepares and simulates the transaction for review.
        case review
        /// Signs and sends the reviewed transaction.
        case send
    }

    /// One run of a step, which the review's task captures.
    nonisolated struct Attempt: Hashable, Sendable {
        /// Identifies the attempt, so a repeated step starts a new task.
        let id = UUID()
        /// What the attempt does.
        let work: Work
    }

    /// The transaction that the person reviews.
    let proposal: Proposal
    /// What the review shows, once the transaction is simulated.
    private(set) var review: Proposal.Review?
    /// The sent transaction's record, as it was saved when the transaction was sent.
    private(set) var record: TransactionRecord?
    /// The error of the last attempt.
    var error: Proposal.Error?
    /// The attempt that's waiting for the review's task, or running.
    private(set) var attempt: Attempt?
    /// What the review prepared, which each simulation uses.
    @ObservationIgnored private var preparation: Proposal.Preparation?
    /// The simulation that the person approves, which can be signed once; each refresh replaces it.
    @ObservationIgnored private var proposed: ProposedTransaction<Proposal.Review>? {
        didSet { isProposed = proposed != nil }
    }
    /// Whether a simulation waits for approval, which views follow instead of each new simulation.
    private var isProposed = false
    private let account: Account
    private let network: Network
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore

    /// The sent transaction's status, which follows its record in the shared transactions.
    var status: TransactionRecord.Status? {
        guard let record else { return nil }
        return transactions.record(record.id, for: record.key)?.status ?? record.status
    }

    /// How the sent transaction settled, or `nil` before it's sent and while it's pending.
    var outcome: TransactionOutcome? { status.flatMap(TransactionOutcome.init) }

    /// The sent transaction's signature and network.
    var submission: Submission? { record?.submission }

    /// Whether the transaction is being signed and sent, or waits to settle.
    var isSending: Bool { attempt?.work == .send || status == .pending }

    /// Whether the person can approve the review: it's simulated, unused, and no step is waiting or running.
    var canApprove: Bool { attempt == nil && isProposed && record == nil }

    /// Starts a review of a proposed transaction; ``prepareReview()`` simulates it.
    /// - Parameters:
    ///   - proposal: The transaction that the person reviews.
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    ///   - transactions: The shared transactions, which simulate, send, record, and watch the transaction.
    /// - Throws: The error of creating the network's transaction coordinator.
    init(_ proposal: Proposal, from account: Account, on network: Network, transactions: TransactionStore) throws {
        coordinator = try transactions.coordinator(for: network)
        self.proposal = proposal
        self.account = account
        self.network = network
        self.transactions = transactions
    }

    /// Asks to prepare and simulate the transaction for review, unless a step is waiting or running or it was sent.
    func prepareReview() {
        guard attempt == nil, record == nil else { return }
        start(.review)
    }

    /// Asks to sign and send the reviewed transaction, unless it can't be approved.
    func approve() {
        guard canApprove else { return }
        start(.send)
    }

    /// Asks to review the same transaction again after it was dropped; the last review shows until the new one
    /// replaces it, and can't be approved meanwhile.
    func tryAgain() {
        guard attempt == nil, outcome == .dropped else { return }
        record = nil
        start(.review)
    }

    /// Repeats the review after an error before anything was sent.
    func retry() {
        guard attempt == nil, record == nil else { return }
        start(.review)
    }

    /// Runs a step once in the review's SwiftUI-managed task.
    /// - Parameter attempt: The attempt that the review's task captured.
    func run(_ attempt: Attempt?) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        switch attempt.work {
        case .review: await prepare()
        case .send: await send()
        }
    }

    /// Simulates the reviewed transaction again, so the review never expires while the person reads it.
    ///
    /// Nothing changes on screen unless the review does. Steps that are waiting or running, and sent transactions,
    /// skip it.
    func refreshReview() async {
        guard canApprove, let preparation else { return }
        do {
            let proposed = try await proposal.simulate(preparation, with: coordinator, from: account)
            // The person may have approved the review meanwhile.
            guard canApprove else { return }
            show(proposed)
        } catch is CancellationError {
            // The review closed.
        } catch {
            // A refresh that fails after the person approved the review, or after it closed, explains nothing.
            guard canApprove, !Task.isCancelled else { return }
            self.error = Self.error(for: error)
        }
    }

    /// Starts a step for the review's task.
    /// - Parameter work: What the step does.
    private func start(_ work: Work) {
        error = nil
        attempt = Attempt(work: work)
    }

    /// Prepares the transaction anew, then simulates it and shows its review.
    private func prepare() async {
        preparation = nil
        proposed = nil
        do {
            let preparation = try await proposal.prepare(from: account, on: network)
            self.preparation = preparation
            show(try await proposal.simulate(preparation, with: coordinator, from: account))
        } catch is CancellationError {
            // The review closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Sends the reviewed transaction, after which its record in the shared transactions shows how it settles.
    ///
    /// A transaction whose delivery is unknown is still recorded and watched, since it may land. A cancelled
    /// authentication uses up the simulation, so a new simulation of the same preparation replaces it.
    private func send() async {
        guard let proposed else { return }
        do {
            record = try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                                 settling: proposed.settling)
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await simulateAgain()
        } catch {
            self.proposed = nil
            self.error = .notSent
        }
    }

    /// Replaces a used simulation with a new one of the same preparation.
    private func simulateAgain() async {
        guard let preparation else { return }
        proposed = nil
        do {
            show(try await proposal.simulate(preparation, with: coordinator, from: account))
        } catch is CancellationError {
            // The review closed.
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Keeps a simulation for approval and shows its review.
    /// - Parameter proposed: The simulation and its review.
    private func show(_ proposed: ProposedTransaction<Proposal.Review>) {
        self.proposed = proposed
        if review != proposed.review { review = proposed.review }
    }

    /// The error that an alert explains.
    /// - Parameter error: A preparation or simulation error.
    /// - Returns: The proposal's error itself, or its preparation failure.
    private static func error(for error: any Swift.Error) -> Proposal.Error {
        error as? Proposal.Error ?? .preparationFailed
    }
}
