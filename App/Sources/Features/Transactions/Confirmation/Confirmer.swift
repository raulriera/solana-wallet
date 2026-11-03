import Foundation
import RPC

/// A confirmer that watches one sent transaction until it lands or can never land.
nonisolated struct Confirmer: TransactionConfirming {
    /// The wait before the first reconnection, which doubles after each failed attempt.
    private static let firstReconnectDelay = Duration.seconds(2)
    private static let longestReconnectDelay = Duration.seconds(60)
    /// How long a connection may go without a root before it counts as lost.
    private static let stallTimeout = Duration.seconds(30)

    private let rpc: any RPC & SignatureEventProviding
    private let clock: any Clock<Duration>

    /// Creates a confirmer.
    ///
    /// - Parameters:
    ///   - rpc: The provider that reads statuses and subscribes on the submission's network.
    ///   - clock: The clock that times stalls and reconnection waits.
    init(rpc: any RPC & SignatureEventProviding, clock: any Clock<Duration> = ContinuousClock()) {
        self.rpc = rpc
        self.clock = clock
    }

    @concurrent
    func confirm(_ submission: Submission) async throws -> Confirmation {
        try Task.checkCancellation()
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
    /// - Parameters:
    ///   - submission: The transaction to watch.
    ///   - schedule: The checks and reconnection wait that every connection shares.
    /// - Returns: The settled outcome.
    /// - Throws: A subscription, read, response, stall, lost connection, or cancellation error.
    private func watch(_ submission: Submission, schedule: inout Schedule) async throws -> Confirmation {
        let events = try await rpc.events(for: submission.signature)
        let checksExpiry = schedule.expiry == nil
        async let catchUpRead = status(of: submission)
        async let epochRead = checksExpiry ? rpc.send(GetEpochInfo()) : nil
        let catchUp = try await catchUpRead
        if let confirmation = settle(catchUp, for: submission, at: schedule.root, schedule: &schedule) {
            return confirmation
        }
        if let epoch = try await epochRead { record(epoch, for: submission, at: schedule.root, schedule: &schedule) }
        if checksExpiry, schedule.expiry != nil {
            if let confirmation = settle(catchUp, for: submission, at: schedule.root, schedule: &schedule) {
                return confirmation
            }
            if let confirmation = try await check(submission, at: schedule.root, schedule: &schedule) {
                return confirmation
            }
        }
        schedule.reconnectDelay = Self.firstReconnectDelay
        while let event = try await next(from: events) {
            try Task.checkCancellation()
            switch event {
            case .landed(let error):
                return Confirmation(submission: submission, slot: nil,
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

    /// Waits for the next event, counting a connection that delivers no root before the stall timeout as lost.
    ///
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

    /// Checks whether the blockhash expired and, once it has, whether the transaction landed first.
    ///
    /// - Parameters:
    ///   - submission: The transaction and its blockhash expiry.
    ///   - root: The newest root.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: The outcome once a status read settles it, or `nil` to keep watching.
    /// - Throws: A read, response, or cancellation error.
    private func check(_ submission: Submission, at root: UInt64, schedule: inout Schedule) async throws -> Confirmation? {
        guard try await hasExpired(submission, at: root, schedule: &schedule) else { return nil }
        let response = try await status(of: submission)
        return settle(response, for: submission, at: root, schedule: &schedule)
    }

    /// Returns the outcome that a status read proves, or schedules the next check.
    ///
    /// - Parameters:
    ///   - response: The transaction's status read.
    ///   - submission: The transaction's receipt.
    ///   - root: The newest root, or `0` before the first one.
    ///   - schedule: The expiry slot, once read, and the next check.
    /// - Returns: The outcome, or `nil` to keep watching.
    private func settle(_ response: GetSignatureStatuses.Response, for submission: Submission, at root: UInt64,
                        schedule: inout Schedule) -> Confirmation? {
        let status = response.value[0]
        if let status, let confirmation = confirmation(of: status, for: submission) { return confirmation }
        guard let expiry = schedule.expiry else { return nil }
        let context = response.context.slot
        if context >= expiry, status == nil {
            return Confirmation(submission: submission, slot: nil, outcome: .dropped)
        }
        schedule.nextCheck = Self.sum(max(root, expiry), context < expiry ? expiry - context : 1)
        return nil
    }

    /// Returns whether the blockhash expired at finalized commitment, reading it unless an earlier read found it.
    ///
    /// - Parameters:
    ///   - submission: The transaction and its last valid block height.
    ///   - root: The newest root.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: Whether a finalized block height above the last valid one was read.
    /// - Throws: A read or cancellation error.
    private func hasExpired(_ submission: Submission, at root: UInt64, schedule: inout Schedule) async throws -> Bool {
        if schedule.expiry != nil { return true }
        record(try await rpc.send(GetEpochInfo()), for: submission, at: root, schedule: &schedule)
        return schedule.expiry != nil
    }

    /// Records the expiry slot once a finalized block height passes the last valid one, or schedules the next check.
    ///
    /// - Parameters:
    ///   - epoch: A finalized epoch read.
    ///   - submission: The transaction and its last valid block height.
    ///   - root: The newest root.
    ///   - schedule: The next check or, once the blockhash has expired, the expiry slot.
    private func record(_ epoch: GetEpochInfo.Response, for submission: Submission, at root: UInt64,
                        schedule: inout Schedule) {
        guard epoch.blockHeight > submission.lastValidBlockHeight else {
            let remaining = submission.lastValidBlockHeight - epoch.blockHeight
            schedule.nextCheck = Self.sum(max(root, epoch.absoluteSlot), Self.sum(remaining, 1))
            return
        }
        schedule.expiry = epoch.absoluteSlot
    }

    /// Reads the transaction's status, including history beyond the recent status cache.
    ///
    /// - Parameter submission: The transaction to look up.
    /// - Returns: The status response for the one signature.
    /// - Throws: ``ConfirmerError/invalidResponse``, an RPC error, or a cancellation error.
    private func status(of submission: Submission) async throws -> GetSignatureStatuses.Response {
        let response = try await rpc.send(GetSignatureStatuses(signatures: [submission.signature]))
        guard response.value.count == 1, (response.value[0]?.slot ?? 0) <= response.context.slot else {
            throw ConfirmerError.invalidResponse
        }
        return response
    }

    /// Returns the outcome of a finalized status.
    ///
    /// - Parameters:
    ///   - status: The transaction's status.
    ///   - submission: The transaction's receipt.
    /// - Returns: The outcome, or `nil` if the status isn't finalized.
    private func confirmation(of status: GetSignatureStatuses.Status, for submission: Submission) -> Confirmation? {
        guard status.confirmationStatus == .finalized else { return nil }
        return Confirmation(submission: submission, slot: status.slot,
                            outcome: status.error.map(Confirmation.Outcome.failed) ?? .succeeded)
    }

    /// Adds a count to a slot, saturating at the largest slot.
    ///
    /// - Parameters:
    ///   - slot: A slot.
    ///   - count: The slots to add.
    /// - Returns: The sum, or `UInt64.max` on overflow.
    private static func sum(_ slot: UInt64, _ count: UInt64) -> UInt64 {
        let (sum, overflow) = slot.addingReportingOverflow(count)
        return overflow ? .max : sum
    }

    /// The state that a watch keeps across reconnections.
    private struct Schedule {
        /// The root at which the next check is due.
        var nextCheck: UInt64 = 0
        /// The newest root received, or `0` before the first.
        var root: UInt64 = 0
        /// The finalized slot whose block height is above the last valid one, or `nil` until read.
        var expiry: UInt64?
        var reconnectDelay = Confirmer.firstReconnectDelay
    }
}
