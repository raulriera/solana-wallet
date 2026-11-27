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
    ///
    /// Once a send with preliminary transactions is sent, it's the review of the proposal's own transaction.
    private(set) var review: Proposal.Review?
    /// The sent transaction's record as saved when it was sent, or `nil` before it's sent.
    ///
    /// A send with preliminary transactions keeps its last transaction's record once that transaction settles.
    private(set) var record: TransactionRecord?
    var error: Proposal.Error?
    /// Why the check of the sent transaction stopped before the transaction settled, or `nil` if it didn't stop.
    private(set) var confirmationError: ConfirmationError?
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
    /// Whether a transaction of the running send landed, so that its fees left the account.
    @ObservationIgnored private var hasLanded = false
    private let account: Account
    private let network: Network
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore
    private let clock: any Clock<Duration>

    /// The most times that a send with preliminary transactions sends a dropped transaction again.
    private static var maximumResends: Int { 2 }

    /// The most times that a send tries its next transaction again after an error that can clear by itself.
    private static var maximumRetries: Int { 2 }

    /// The sent transaction's outcome, or `nil` before it's sent.
    var outcome: TransactionOutcome? {
        guard let record else { return nil }
        return transactions.record(record.id, for: record.key)?.outcome
    }

    /// Why a send ended before its own transaction because the check of a preliminary transaction stopped, or `nil`.
    var unfinishedSendError: ConfirmationError? {
        get { attempt == nil && record == nil ? confirmationError : nil }
        set { confirmationError = newValue }
    }

    /// Whether the transaction is being signed and sent, or waits to settle while its check runs.
    var isSending: Bool { attempt?.work == .send || (outcome?.status == .pending && confirmationError == nil) }

    /// Whether the transaction is being signed and sent, or was sent.
    var isSent: Bool { isSending || outcome != nil }

    var canApprove: Bool { attempt == nil && isProposed && record == nil }

    /// The error that ends the running send: not finished once one of its transactions landed, otherwise not sent.
    private var sendError: Proposal.Error { hasLanded ? .notFinished : .notSent }

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
    ///
    /// After an error, it simulates the preparation that the error kept, if any, instead of preparing again.
    func prepareReview() {
        guard attempt == nil, record == nil else { return }
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
        guard attempt == nil, outcome?.status == .dropped else { return }
        record = nil
        start(.review)
    }

    /// Waits for the sent transaction to settle, and keeps why its check stopped if it stops first, unless it stopped
    /// already.
    func watchOutcome() async {
        guard let record, confirmationError == nil else { return }
        do {
            _ = try await transactions.watch(record.id, for: record.key)
        } catch is CancellationError {
        } catch {
            confirmationError = ConfirmationError(error)
        }
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
    ///
    /// An error shows, and the preparation stays for the next refresh.
    func refreshReview() async {
        guard canApprove, let preparation else { return }
        do {
            let proposed = try await proposal.simulate(preparation, with: coordinator, from: account)
            guard canApprove else { return }
            show(proposed)
        } catch is CancellationError {
        } catch {
            guard canApprove, !Task.isCancelled else { return }
            show(error, otherwise: .preparationFailed, keepingPreparation: true)
        }
    }

    /// Stops a running send with preliminary transactions before it sends its next transaction: the send ends when
    /// the transaction that was sent settles, or when the next transaction is prepared.
    ///
    /// The next attempt starts without the stop, so a stop while no send runs has no effect.
    func stopSending() {
        isStopping = true
    }

    /// Starts an attempt.
    ///
    /// - Parameter work: The attempt's work.
    private func start(_ work: Work) {
        error = nil
        confirmationError = nil
        isStopping = false
        hasLanded = false
        attempt = Attempt(work: work)
    }

    /// Prepares the transaction, unless a preparation is kept, simulates it, and shows its review.
    private func prepare() async {
        proposed = nil
        do {
            show(try await simulate())
        } catch is CancellationError {
        } catch {
            show(error, otherwise: .preparationFailed)
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
    /// error shows as the proposal's not-finished error once one of the send's transactions landed, and as its not-sent
    /// error before. A preliminary transaction whose check stops ends the send with only the stop's reason.
    private func send() async {
        guard let proposed else { return }
        do {
            if proposed.isPreliminary {
                let sent = try await coordinator.withSharedAuthentication { coordinator in
                    try await self.sendInSteps(startingWith: proposed, using: coordinator)
                }
                if review != sent.review { review = sent.review }
                record = sent.record
            } else {
                record = try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                                     settling: proposed.settling)
            }
        } catch let error as ConfirmationError {
            confirmationError = error
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await prepare()
        } catch {
            self.proposed = nil
            show(error, otherwise: sendError)
        }
    }

    /// Sends the proposal's preliminary transactions and then its own: it sends each transaction, waits for it to
    /// settle, and prepares the next one. A transaction whose check stops ends the send and keeps the stop's reason.
    /// It sends a dropped transaction again only with the same preparation, and ends when the proposal
    /// rejects that preparation, so that a transaction that landed despite a drop can't be paid again with a new
    /// preparation.
    ///
    /// Once the first transaction is sent, its simulation no longer waits for approval.
    ///
    /// - Parameters:
    ///   - first: The approved simulation of the first preliminary transaction.
    ///   - coordinator: The coordinator whose signatures share one authentication.
    /// - Returns: The record of the proposal's own transaction, and that transaction's review.
    /// - Throws: ``ConfirmationError`` if the check of a preliminary transaction stopped;
    ///   ``Error/endedBeforeNextTransaction`` if the send was stopped while it prepared the next transaction,
    ///   or that transaction needs more transactions than the person approved with the first one; the proposal's
    ///   not-finished error, or its not-sent error before a transaction landed, if a preliminary transaction didn't
    ///   succeed or the send was stopped before it prepared the next transaction; the proposal's error if it rejects
    ///   the next transaction or the preparation of a dropped one; `CancellationError` if the person cancels
    ///   authentication, or the task or a watch is cancelled; or a preparation, signing, or storage error.
    private func sendInSteps(startingWith first: ProposedTransaction<Proposal.Review>,
                             using coordinator: any TransactionCoordinating) async throws
        -> (record: TransactionRecord, review: Proposal.Review) {
        var proposed = first
        var resends = 0
        var approvedTransactions = first.followingTransactions
        while true {
            let sent = try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                                   settling: proposed.settling, using: coordinator)
            self.proposed = nil
            let settled: TransactionOutcome
            do {
                settled = try await outcome(of: sent)
            } catch let error as ConfirmationError where !proposed.isPreliminary {
                confirmationError = error
                return (sent, proposed.review)
            }
            if settled.status != .dropped { hasLanded = true }
            switch settled.status {
            case .succeeded where proposed.isPreliminary:
                resends = 0
                preparation = nil
                approvedTransactions -= 1
            case .dropped where resends < Self.maximumResends: resends += 1
            case .pending, .succeeded, .dropped, .failed:
                guard !proposed.isPreliminary else {
                    try Task.checkCancellation()
                    throw sendError
                }
                return (sent, proposed.review)
            }
            guard !isStopping else { throw sendError }
            try Task.checkCancellation()
            proposed = try await simulate(retryingUpTo: Self.maximumRetries, preparingAgain: false)
            try Task.checkCancellation()
            guard !isStopping, proposed.followingTransactions <= approvedTransactions else {
                throw Error.endedBeforeNextTransaction
            }
        }
    }

    /// Waits for a sent transaction's settled outcome.
    ///
    /// - Parameter sent: The sent transaction's record.
    /// - Returns: The transaction's settled outcome.
    /// - Throws: ``ConfirmationError`` if its check stops, or `CancellationError` if the task or the watch is cancelled.
    private func outcome(of sent: TransactionRecord) async throws -> TransactionOutcome {
        do {
            return try await transactions.watch(sent.id, for: sent.key)
        } catch where !(error is CancellationError) {
            throw ConfirmationError(error)
        }
    }

    /// Simulates the kept preparation, or prepares the transaction and simulates its preparation.
    ///
    /// When it may prepare again, it prepares the transaction again only if the proposal reports the kept preparation
    /// as failed. After an error that can clear by itself, it waits with a doubling backoff and tries again, reusing
    /// any preparation that it kept.
    ///
    /// - Parameters:
    ///   - maximumRetries: The most times that it tries again after an error that can clear by itself.
    ///   - preparingAgain: Whether it replaces a kept preparation that the proposal reports as failed.
    /// - Returns: The simulation of the transaction.
    /// - Throws: A preparation, simulation, or cancellation error.
    private func simulate(retryingUpTo maximumRetries: Int = 0, preparingAgain: Bool = true) async throws
        -> ProposedTransaction<Proposal.Review> {
        var retries = 0
        var backoff = Backoff.reconnection
        var mayPrepareAgain = preparingAgain && preparation != nil
        while true {
            do {
                return try await proposal.simulate(try await prepared(), with: coordinator, from: account)
            } catch let error as RPCError where error.isRecoverable && retries < maximumRetries {
                retries += 1
                try await clock.sleep(for: backoff.next())
            } catch let error as Proposal.Error where mayPrepareAgain && error == .preparationFailed {
                mayPrepareAgain = false
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

    /// Shows an error as the proposal's error itself or a fallback, and forgets the preparation unless it's kept, the
    /// error can clear by itself, or the send ended before its next transaction.
    ///
    /// - Parameters:
    ///   - error: The error that ended a review, a refresh, or a send.
    ///   - fallback: The error to show when the error isn't the proposal's.
    ///   - keepingPreparation: Whether the next review simulates the same preparation whatever the error.
    private func show(_ error: any Swift.Error, otherwise fallback: Proposal.Error, keepingPreparation: Bool = false) {
        switch error {
        case _ where keepingPreparation: break
        case Error.endedBeforeNextTransaction: break
        case let error as RPCError where error.isRecoverable: break
        default: preparation = nil
        }
        self.error = error as? Proposal.Error ?? fallback
    }
}

extension TransactionReviewModel: IdentityHashable {}
