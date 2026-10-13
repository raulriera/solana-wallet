import Foundation
import RPC

/// Watches one sent transaction in real time until it lands or can never land.
///
/// One connection carries the signature subscription, which reports the landing, and the root subscription,
/// which schedules finalized block-height reads. A finalized block height above the blockhash's last valid one
/// proves that no later block can include the transaction; a status read then shows whether an earlier one did.
nonisolated struct Confirmer: TransactionConfirming {
    /// The wait before the first reconnection; each failed attempt doubles it.
    private static let firstReconnectDelay = Duration.seconds(2)
    /// The longest wait between reconnections.
    private static let longestReconnectDelay = Duration.seconds(60)
    /// How long a connection may go without a root before the watch counts it as lost.
    private static let stallTimeout = Duration.seconds(30)

    private let rpc: any RPC & SignatureEventProviding
    private let clock: any Clock<Duration>

    /// Creates a watch that reads and subscribes through one provider.
    ///
    /// - Parameters:
    ///   - rpc: The provider serving the submission's network, for status reads and subscriptions.
    ///   - clock: The clock that times stalled connections and reconnection waits; continuous time is the default.
    init(rpc: any RPC & SignatureEventProviding, clock: any Clock<Duration> = ContinuousClock()) {
        self.rpc = rpc
        self.clock = clock
    }

    /// Watches the transaction until it lands at confirmed commitment or its blockhash expires without it.
    ///
    /// After each subscription, one status read catches up on an earlier landing; once the blockhash has expired, it is
    /// also the final read. Before that, a finalized epoch read checks the expiry, and a status read follows the one
    /// that finds it. Roots schedule later checks.
    /// An error that `RPCError.isRecoverable` accepts, or 30 seconds without a root, reconnects after 2 seconds,
    /// doubling the wait up to a minute until a subscription and its first reads succeed; the schedule carries over.
    /// Rate limits, rejected keys, refused subscriptions, and malformed responses throw. The watch has no deadline,
    /// and nothing rebuilds, resigns, or resubmits the transaction.
    ///
    /// - Parameter submission: The accepted signature, original network, and blockhash expiry.
    /// - Returns: A confirmed or finalized execution outcome, or finalized proof that the transaction was dropped.
    /// - Throws: ``ConfirmerError``, an RPC error that reconnecting can't clear, or `CancellationError`.
    @concurrent
    func confirm(_ submission: Submission) async throws -> Confirmation {
        try Task.checkCancellation()
        guard rpc.network == submission.network else { throw ConfirmerError.networkMismatch }
        var schedule = Schedule()
        while true {
            do {
                return try await watch(submission, schedule: &schedule)
            } catch {
                try Task.checkCancellation()
                guard (error as? RPCError)?.isRecoverable == true else { throw error }
            }
            try await clock.sleep(for: schedule.reconnectDelay)
            schedule.reconnectDelay = min(schedule.reconnectDelay * 2, Self.longestReconnectDelay)
        }
    }

    /// Subscribes once, then follows the landing and roots until the outcome settles or the connection fails.
    ///
    /// The reconnection wait resets once the subscription and its first reads succeed.
    /// Returning or throwing releases the stream, which closes its connection.
    /// - Parameters:
    ///   - submission: The transaction to watch.
    ///   - schedule: The checks and reconnection wait that every connection shares.
    /// - Returns: The settled outcome.
    /// - Throws: A subscription, read, response, stall, or cancellation error; a stream that ends counts as a
    ///   lost connection.
    private func watch(_ submission: Submission, schedule: inout Schedule) async throws -> Confirmation {
        let events = try await rpc.events(for: submission.signature)
        // The subscription can miss a landing from before it started; after expiry, this read is also the final one.
        let catchUp = try await status(of: submission)
        if let confirmation = settle(catchUp, for: submission, at: schedule.root, schedule: &schedule) {
            return confirmation
        }
        if schedule.expiry == nil, let confirmation = try await check(submission, at: schedule.root, schedule: &schedule) {
            return confirmation
        }
        schedule.reconnectDelay = Self.firstReconnectDelay
        while let event = try await next(from: events) {
            try Task.checkCancellation()
            switch event {
            case .landed(let error):
                return Confirmation(submission: submission, slot: nil, commitment: .confirmed,
                                    outcome: error.map(Confirmation.Outcome.failed) ?? .succeeded)
            case .rooted(let root):
                schedule.root = root
                guard root >= schedule.nextCheck else { continue }
                if let confirmation = try await check(submission, at: root, schedule: &schedule) {
                    return confirmation
                }
            }
        }
        try Task.checkCancellation()
        throw RPCError.transport(.networkConnectionLost)
    }

    /// Waits for the next event, counting a connection that delivers no root for 30 seconds as lost.
    ///
    /// A stall stops waiting on the stream, which closes its connection.
    /// - Parameter events: The connection's landing and roots.
    /// - Returns: The next event, or `nil` when the stream ends.
    /// - Throws: `RPCError.transport(.timedOut)` after a stall, the stream's error, or a cancellation error.
    private func next(from events: AsyncThrowingStream<SignatureEvent, any Error>) async throws -> SignatureEvent? {
        try await withThrowingTaskGroup(of: SignatureEvent?.self) { group in
            group.addTask {
                var iterator = events.makeAsyncIterator()
                return try await iterator.next()
            }
            group.addTask {
                try await clock.sleep(for: Self.stallTimeout)
                throw RPCError.transport(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }

    /// Reads whether the blockhash expired at finalized commitment and, once it has, whether the transaction landed first.
    ///
    /// - Parameters:
    ///   - submission: The transaction and its blockhash expiry.
    ///   - root: The newest root, from which the next check is scheduled.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: The outcome once a status read settles it, or `nil` to keep watching.
    /// - Throws: A read, response, or cancellation error.
    private func check(_ submission: Submission, at root: UInt64, schedule: inout Schedule) async throws -> Confirmation? {
        guard try await hasExpired(submission, at: root, schedule: &schedule) else { return nil }
        let response = try await status(of: submission)
        return settle(response, for: submission, at: root, schedule: &schedule)
    }

    /// Settles a status read: a confirmed status gives its outcome, and once the blockhash has expired, a missing
    /// status from a node that has reached the expiry slot proves the transaction was dropped.
    ///
    /// After expiry, a node behind the expiry slot is read again once roots advance by the slots it lags; a status
    /// that isn't confirmed yet is read again on the next root.
    /// - Parameters:
    ///   - response: The transaction's status read.
    ///   - submission: The receipt that the outcome belongs to.
    ///   - root: The newest root, or `0` before the first one, from which the next check is scheduled.
    ///   - schedule: The expiry slot, once read, and the next check.
    /// - Returns: The outcome, or `nil` to keep watching.
    private func settle(_ response: GetSignatureStatuses.Response, for submission: Submission, at root: UInt64,
                        schedule: inout Schedule) -> Confirmation? {
        let status = response.value[0]
        if let status, let confirmation = confirmation(of: status, for: submission) { return confirmation }
        guard let expiry = schedule.expiry else { return nil }
        let context = response.context.slot
        if context >= expiry, status == nil {
            return Confirmation(submission: submission, slot: nil, commitment: .finalized, outcome: .dropped)
        }
        // Before the first root, the expiry slot stands in for it.
        schedule.nextCheck = Self.sum(max(root, expiry), context < expiry ? expiry - context : 1)
        return nil
    }

    /// Reads whether the blockhash expired at finalized commitment, recording the expiry slot once it has, and
    /// schedules the next check while it's valid.
    ///
    /// Block height grows by at most one per slot, so the next check waits for a root past the slots that the
    /// remaining heights need. A root ahead of the finalized slot moves the check past that root.
    /// - Parameters:
    ///   - submission: The transaction and its last valid block height.
    ///   - root: The newest root.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: Whether a finalized block height above the last valid one was read.
    /// - Throws: A read or cancellation error.
    private func hasExpired(_ submission: Submission, at root: UInt64, schedule: inout Schedule) async throws -> Bool {
        if schedule.expiry != nil { return true }
        let epoch = try await rpc.send(GetEpochInfo(commitment: .finalized))
        guard epoch.blockHeight > submission.lastValidBlockHeight else {
            let remaining = submission.lastValidBlockHeight - epoch.blockHeight
            schedule.nextCheck = Self.sum(max(root, epoch.absoluteSlot), Self.sum(remaining, 1))
            return false
        }
        schedule.expiry = epoch.absoluteSlot
        return true
    }

    /// Reads the transaction's status, searching history beyond the recent status cache.
    ///
    /// - Parameter submission: The transaction to look up without sending it.
    /// - Returns: The response, describing exactly the one signature at or before its context slot.
    /// - Throws: ``ConfirmerError/invalidResponse``, an RPC error, or a cancellation error.
    private func status(of submission: Submission) async throws -> GetSignatureStatuses.Response {
        let response = try await rpc.send(GetSignatureStatuses(signatures: [submission.signature],
                                                               searchesTransactionHistory: true))
        guard response.value.count == 1, (response.value[0]?.slot ?? 0) <= response.context.slot else {
            throw ConfirmerError.invalidResponse
        }
        return response
    }

    /// Settles a status once its commitment is confirmed or finalized, keeping execution failures as outcomes.
    ///
    /// - Parameters:
    ///   - status: The transaction's status.
    ///   - submission: The receipt that the outcome belongs to.
    /// - Returns: The outcome, or `nil` for a processed status or one without a commitment.
    private func confirmation(of status: GetSignatureStatuses.Status, for submission: Submission) -> Confirmation? {
        guard let commitment = status.confirmationStatus, commitment != .processed else { return nil }
        return Confirmation(submission: submission, slot: status.slot, commitment: commitment,
                            outcome: status.error.map(Confirmation.Outcome.failed) ?? .succeeded)
    }

    /// Adds slot counts, saturating instead of overflowing on values that no ledger reaches.
    ///
    /// - Parameters:
    ///   - slot: A slot.
    ///   - count: The slots to add.
    /// - Returns: The sum, or the largest slot when the sum isn't representable.
    private static func sum(_ slot: UInt64, _ count: UInt64) -> UInt64 {
        let (sum, overflow) = slot.addingReportingOverflow(count)
        return overflow ? .max : sum
    }

    /// What a watch keeps across reconnections.
    private struct Schedule {
        /// The root from which the next check is due.
        var nextCheck: UInt64 = 0
        /// The newest root received.
        var root: UInt64 = 0
        /// The finalized slot whose block height is above the last valid one, once read.
        var expiry: UInt64?
        /// The wait before the next reconnection.
        var reconnectDelay = Confirmer.firstReconnectDelay
    }
}
