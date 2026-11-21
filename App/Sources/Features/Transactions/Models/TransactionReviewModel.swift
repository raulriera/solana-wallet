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

    /// An end of a send with preliminary transactions after its next transaction is prepared.
    private nonisolated enum Error: Swift.Error {
        /// The send stopped, or its next transaction needs more transactions than the person approved.
        case endedBeforeNextTransaction
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
    /// Whether a send with preliminary transactions ends before its next transaction.
    @ObservationIgnored private var isStopping = false
    private let account: Account
    private let network: Network
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore
    private let clock: any Clock<Duration>

    /// The most times that a send with preliminary transactions sends a dropped transaction again.
    private static var maximumResends: Int { 2 }

    /// The most times that a send tries its next transaction again after an error that can clear by itself.
    private static var maximumRetries: Int { 2 }

    /// How the sent transaction settled, or `nil` before it's sent and while it's pending.
    var outcome: TransactionOutcome? {
        guard let record else { return nil }
        return transactions.record(record.id, for: record.key)?.outcome
    }

    var submission: Submission? { record?.submission }

    /// Whether the transaction is being signed and sent, or waits to settle.
    var isSending: Bool { attempt?.work == .send || (record != nil && outcome == nil) }

    var canApprove: Bool { attempt == nil && isProposed && record == nil }

    /// Creates a review of a proposed transaction.
    ///
    /// - Parameters:
    ///   - proposal: The transaction that the person reviews.
    ///   - account: The account that signs and pays.
    ///   - network: The network that the transaction is sent on.
    ///   - transactions: The store that sends, records, and watches the transaction.
    ///   - clock: The clock that times the waits before a send tries its next transaction again.
    /// - Throws: An error if the network's transaction coordinator can't be created.
    init(_ proposal: Proposal, from account: Account, on network: Network, transactions: TransactionStore,
         clock: any Clock<Duration> = ContinuousClock()) throws {
        coordinator = try transactions.coordinator(for: network)
        self.proposal = proposal
        self.account = account
        self.network = network
        self.transactions = transactions
        self.clock = clock
    }

    /// Starts preparing and simulating the transaction, unless a step is waiting or running or it was sent.
    func prepareReview() {
        guard attempt == nil, record == nil else { return }
        preparation = nil
        start(.review)
    }

    /// Starts signing and sending the reviewed transaction, unless it can't be approved.
    func approve() {
        guard canApprove else { return }
        start(.send)
    }

    /// Starts a new review of a dropped transaction, unless a step is waiting or running.
    ///
    /// The review simulates the same preparation again, and prepares the transaction again only if the proposal
    /// rejects that preparation.
    func tryAgain() {
        guard attempt == nil, outcome == .dropped else { return }
        record = nil
        start(.review)
    }

    /// Starts the review again after an error, unless the transaction was sent.
    ///
    /// It simulates the same preparation again when the error could clear by itself, or when the send ended before its
    /// next transaction.
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
            show(error)
        }
    }

    /// Stops a send before it sends its next transaction: the send ends when the transaction that was sent has an
    /// outcome, or when the next transaction is prepared.
    func stopSending() {
        guard attempt?.work == .send else { return }
        isStopping = true
    }

    /// Starts an attempt.
    ///
    /// - Parameter work: The attempt's work.
    private func start(_ work: Work) {
        error = nil
        isStopping = false
        attempt = Attempt(work: work)
    }

    /// Prepares the transaction, unless a preparation is kept, simulates it, and shows its review.
    private func prepare() async {
        proposed = nil
        do {
            show(try await simulate())
        } catch is CancellationError {
        } catch {
            show(error)
        }
    }

    /// Returns the kept preparation, or prepares the transaction and keeps its preparation.
    ///
    /// - Returns: The transaction's preparation.
    /// - Throws: A preparation or cancellation error.
    private func prepared() async throws -> Proposal.Preparation {
        if let preparation { return preparation }
        let prepared = try await proposal.prepare(from: account, on: network)
        preparation = prepared
        return prepared
    }

    /// Signs and sends the reviewed transaction and keeps its record, after any preliminary transactions.
    ///
    /// An error of the proposal, such as a next transaction that the account can't pay for, shows as itself; any other
    /// error shows as the proposal's not-sent error.
    private func send() async {
        guard let proposed else { return }
        do {
            record = proposed.isPreliminary
                ? try await coordinator.withSharedAuthentication { coordinator in
                    try await self.sendInSteps(startingWith: proposed, using: coordinator)
                }
                : try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                              settling: proposed.settling)
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await prepare()
        } catch {
            self.proposed = nil
            forgetPreparation(after: error)
            self.error = error as? Proposal.Error ?? .notSent
        }
    }

    /// Sends the proposal's preliminary transactions and then its own: it sends each transaction, waits for its
    /// outcome, and prepares the next one, sending a dropped one again with the same preparation.
    ///
    /// - Parameters:
    ///   - first: The approved simulation of the first preliminary transaction.
    ///   - coordinator: The coordinator whose signatures share one authentication.
    /// - Returns: The record of the proposal's own transaction.
    /// - Throws: ``Error/endedBeforeNextTransaction`` if the send was stopped while it prepared the next transaction,
    ///   or that transaction needs more transactions than the person approved with the first one; the proposal's
    ///   not-sent error if a preliminary transaction didn't succeed or the send was stopped before it prepared the
    ///   next transaction; `CancellationError` if the person cancels authentication; or a preparation, signing, or
    ///   storage error.
    private func sendInSteps(startingWith first: ProposedTransaction<Proposal.Review>,
                             using coordinator: any TransactionCoordinating) async throws -> TransactionRecord {
        var proposed = first
        var resends = 0
        var approvedTransactions = first.followingTransactions
        while true {
            let sent = try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                                   settling: proposed.settling, using: coordinator)
            switch try? await transactions.watch(sent.id, for: sent.key) {
            case .succeeded? where proposed.isPreliminary:
                resends = 0
                preparation = nil
                approvedTransactions -= 1
            case .dropped? where resends < Self.maximumResends: resends += 1
            case .succeeded?, .dropped?, .failed?, nil:
                guard !proposed.isPreliminary else { throw Proposal.Error.notSent }
                return sent
            }
            guard !isStopping else { throw Proposal.Error.notSent }
            try Task.checkCancellation()
            proposed = try await simulate(retryingUpTo: Self.maximumRetries)
            guard !isStopping, proposed.followingTransactions <= approvedTransactions else {
                throw Error.endedBeforeNextTransaction
            }
        }
    }

    /// Simulates the kept preparation, or prepares the transaction and simulates its preparation.
    ///
    /// It prepares the transaction again only if the proposal rejects the kept preparation, and after an error that can
    /// clear by itself, it waits with a doubling backoff and tries again, reusing any preparation that it kept.
    ///
    /// - Parameter maximumRetries: The most times that it tries again after an error that can clear by itself.
    /// - Returns: The simulation of the transaction.
    /// - Throws: A preparation, simulation, or cancellation error.
    private func simulate(retryingUpTo maximumRetries: Int = 0) async throws -> ProposedTransaction<Proposal.Review> {
        var retries = 0
        var backoff = Backoff.reconnection
        var reusesPreparation = preparation != nil
        while true {
            do {
                return try await proposal.simulate(try await prepared(), with: coordinator, from: account)
            } catch let error as RPCError where error.isRecoverable && retries < maximumRetries {
                retries += 1
                try await clock.sleep(for: backoff.next())
            } catch is Proposal.Error where reusesPreparation {
                reusesPreparation = false
                preparation = nil
            }
        }
    }

    /// Keeps a simulation for approval and shows its review.
    ///
    /// - Parameter proposed: The simulation and its review.
    private func show(_ proposed: ProposedTransaction<Proposal.Review>) {
        self.proposed = proposed
        if review != proposed.review { review = proposed.review }
    }

    /// Shows a preparation or simulation error as the proposal's error itself or its preparation failure.
    ///
    /// - Parameter error: A preparation or simulation error.
    private func show(_ error: any Swift.Error) {
        forgetPreparation(after: error)
        self.error = error as? Proposal.Error ?? .preparationFailed
    }

    /// Forgets the preparation, unless the error can clear by itself or the send ended before its next transaction,
    /// and the next review can simulate the same preparation again.
    ///
    /// - Parameter error: The error that ended a review or a send.
    private func forgetPreparation(after error: any Swift.Error) {
        switch error {
        case Error.endedBeforeNextTransaction: return
        case let error as RPCError where error.isRecoverable: return
        default: preparation = nil
        }
    }
}

extension TransactionReviewModel: IdentityHashable {}
