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
    /// Whether a send with preliminary transactions ends before its next transaction.
    @ObservationIgnored private var isStopping = false
    private let account: Account
    private let network: Network
    private let coordinator: any TransactionCoordinating
    private let transactions: TransactionStore

    /// The most times that a send with preliminary transactions sends a dropped transaction again.
    private static var maximumResends: Int { 2 }

    /// The most times that a send prepares its next transaction again after an error that can clear by itself.
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

    /// Stops a send before its next transaction, when the transaction that was sent has an outcome.
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

    /// Signs and sends the reviewed transaction and keeps its record, after any preliminary transactions.
    private func send() async {
        guard let proposed else { return }
        do {
            let sent = proposed.isPreliminary
                ? try await sendInSteps(startingWith: proposed)
                : try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                              settling: proposed.settling)
            guard let sent else {
                self.proposed = nil
                self.error = .notSent
                return
            }
            record = sent
        } catch is CancellationError {
            guard !Task.isCancelled else { return }
            await simulateAgain()
        } catch {
            self.proposed = nil
            self.error = .notSent
        }
    }

    /// Sends the proposal's preliminary transactions and then its own, with one authentication for all of them.
    ///
    /// - Parameter first: The approved simulation of the first preliminary transaction.
    /// - Returns: The record of the proposal's own transaction, or `nil` if a preliminary transaction didn't succeed
    ///   or the send was stopped.
    /// - Throws: `CancellationError` if the person cancels authentication, or a preparation, signing, or storage
    ///   error.
    private func sendInSteps(startingWith first: ProposedTransaction<Proposal.Review>) async throws
        -> TransactionRecord? {
        try await coordinator.withSharedAuthentication { coordinator in
            try await self.sendInSteps(startingWith: first, using: coordinator)
        }
    }

    /// Sends each transaction, waits for its outcome, and prepares the next one, sending a dropped one again.
    ///
    /// - Parameters:
    ///   - first: The approved simulation of the first preliminary transaction.
    ///   - coordinator: The coordinator whose signatures share one authentication.
    /// - Returns: The record of the proposal's own transaction, or `nil` if a preliminary transaction didn't succeed
    ///   or the send was stopped.
    /// - Throws: `CancellationError` if the person cancels authentication, or a preparation, signing, or storage
    ///   error.
    private func sendInSteps(startingWith first: ProposedTransaction<Proposal.Review>,
                             using coordinator: any TransactionCoordinating) async throws -> TransactionRecord? {
        var proposed = first
        var resends = 0
        while true {
            let sent = try await transactions.send(proposed.simulation, as: proposed.kind, from: account,
                                                   settling: proposed.settling, using: coordinator)
            preparation = nil
            switch try? await transactions.watch(sent.id, for: sent.key) {
            case .succeeded? where proposed.isPreliminary: resends = 0
            case .dropped? where resends < Self.maximumResends: resends += 1
            case .succeeded?, .dropped?, .failed?, nil: return proposed.isPreliminary ? nil : sent
            }
            guard !isStopping else { return nil }
            try Task.checkCancellation()
            proposed = try await nextProposed(using: coordinator)
        }
    }

    /// Prepares and simulates the proposal's next transaction, trying again after an error that can clear by itself.
    ///
    /// - Parameter coordinator: The coordinator whose signatures share one authentication.
    /// - Returns: The simulation of the next transaction.
    /// - Throws: A preparation or cancellation error.
    private func nextProposed(using coordinator: any TransactionCoordinating) async throws
        -> ProposedTransaction<Proposal.Review> {
        var retries = 0
        while true {
            do {
                let preparation = try await proposal.prepare(from: account, on: network)
                return try await proposal.simulate(preparation, with: coordinator, from: account)
            } catch let error as RPCError where error.isRecoverable && retries < Self.maximumRetries {
                retries += 1
            }
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
