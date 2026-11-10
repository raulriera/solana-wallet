import Foundation
import Observation
import RPC
import Transactions

/// One review of a proposed transaction: what it shows, its approval, and how the sent transaction settled.
@MainActor
@Observable
final class TransactionReviewModel<Proposal: TransactionProposal>: Identifiable {
    /// The work of an attempt.
    nonisolated enum Work: Hashable, Sendable {
        /// Prepares and simulates the transaction for review.
        case review
        /// Signs and sends the reviewed transaction.
        case send
    }

    /// One run of a step.
    nonisolated struct Attempt: Hashable, Sendable {
        let id = UUID()
        let work: Work
    }

    let proposal: Proposal
    /// What the review shows, or `nil` before the transaction is simulated.
    private(set) var review: Proposal.Review?
    /// The sent transaction's record as saved when it was sent, or `nil` before it's sent.
    private(set) var record: TransactionRecord?
    var error: Proposal.Error?
    /// The attempt that's waiting or running, or `nil` for none.
    private(set) var attempt: Attempt?
    @ObservationIgnored private var preparation: Proposal.Preparation?
    /// The simulation that the person approves; each refresh replaces it.
    @ObservationIgnored private var proposed: ProposedTransaction<Proposal.Review>? {
        didSet { isProposed = proposed != nil }
    }
    /// Whether a simulation waits for approval.
    private var isProposed = false
    private let account: Account
    private let network: Network
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore

    /// The sent transaction's current status, or `nil` before it's sent.
    var status: TransactionRecord.Status? {
        guard let record else { return nil }
        return transactions.record(record.id, for: record.key)?.status ?? record.status
    }

    /// How the sent transaction settled, or `nil` before it's sent and while it's pending.
    var outcome: TransactionOutcome? { status.flatMap(TransactionOutcome.init) }

    var submission: Submission? { record?.submission }

    /// Whether the transaction is being signed and sent, or waits to settle.
    var isSending: Bool { attempt?.work == .send || status == .pending }

    var canApprove: Bool { attempt == nil && isProposed && record == nil }

    /// Creates a review of a proposed transaction.
    ///
    /// - Parameters:
    ///   - proposal: The transaction that the person reviews.
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    ///   - transactions: The store that sends, records, and watches the transaction.
    /// - Throws: An error if the network's transaction coordinator can't be created.
    init(_ proposal: Proposal, from account: Account, on network: Network, transactions: TransactionStore) throws {
        coordinator = try transactions.coordinator(for: network)
        self.proposal = proposal
        self.account = account
        self.network = network
        self.transactions = transactions
    }

    /// Starts preparing and simulating the transaction, unless a step is waiting or running or it was sent.
    func prepareReview() {
        guard attempt == nil, record == nil else { return }
        start(.review)
    }

    /// Starts signing and sending the reviewed transaction, unless it can't be approved.
    func approve() {
        guard canApprove else { return }
        start(.send)
    }

    /// Starts a new review of a dropped transaction.
    func tryAgain() {
        guard attempt == nil, outcome == .dropped else { return }
        record = nil
        start(.review)
    }

    /// Starts the review again after an error, unless the transaction was sent.
    func retry() {
        guard attempt == nil, record == nil else { return }
        start(.review)
    }

    /// Runs an attempt's step once.
    ///
    /// - Parameter attempt: The attempt to run, or `nil` for none.
    func run(_ attempt: Attempt?) async {
        guard let attempt, self.attempt == attempt else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        switch attempt.work {
        case .review: await prepare()
        case .send: await send()
        }
    }

    /// Simulates the reviewed transaction again, unless a step is waiting or running or it was sent.
    func refreshReview() async {
        guard canApprove, let preparation else { return }
        do {
            let proposed = try await proposal.simulate(preparation, with: coordinator, from: account)
            guard canApprove else { return }
            show(proposed)
        } catch is CancellationError {
        } catch {
            guard canApprove, !Task.isCancelled else { return }
            self.error = Self.error(for: error)
        }
    }

    /// Starts an attempt.
    ///
    /// - Parameter work: The attempt's work.
    private func start(_ work: Work) {
        error = nil
        attempt = Attempt(work: work)
    }

    /// Prepares and simulates the transaction, then shows its review.
    private func prepare() async {
        preparation = nil
        proposed = nil
        do {
            let preparation = try await proposal.prepare(from: account, on: network)
            self.preparation = preparation
            show(try await proposal.simulate(preparation, with: coordinator, from: account))
        } catch is CancellationError {
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Signs and sends the reviewed transaction and keeps its record.
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
        } catch {
            self.error = Self.error(for: error)
        }
    }

    /// Keeps a simulation for approval and shows its review.
    ///
    /// - Parameter proposed: The simulation and its review.
    private func show(_ proposed: ProposedTransaction<Proposal.Review>) {
        self.proposed = proposed
        if review != proposed.review { review = proposed.review }
    }

    /// Returns the review error for a preparation or simulation error.
    ///
    /// - Parameter error: A preparation or simulation error.
    /// - Returns: The proposal's error itself, or its preparation failure.
    private static func error(for error: any Swift.Error) -> Proposal.Error {
        error as? Proposal.Error ?? .preparationFailed
    }
}

extension TransactionReviewModel: IdentityHashable {}
