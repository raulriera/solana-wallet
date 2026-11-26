import Foundation
import RPC
import Transactions

/// A confirmer that watches one sent transaction until it lands or can never land.
nonisolated struct Confirmer: TransactionConfirming {
    /// How long a connection may go without a root before it counts as lost.
    private static let stallTimeout = Duration.seconds(30)

    private let rpc: any RPC & SignatureEventProviding
    private let clock: any Clock<Duration>

    /// Creates a confirmer.
    ///
    /// - Parameters:
    ///   - rpc: The provider that reads statuses and subscribes on the transaction's network.
    ///   - clock: The clock that times stalls and reconnection waits.
    init(rpc: any RPC & SignatureEventProviding, clock: any Clock<Duration> = ContinuousClock()) {
        self.rpc = rpc
        self.clock = clock
    }

    @concurrent
    func confirm(_ pending: TransactionOutcome, of transaction: Transaction) async throws -> TransactionOutcome {
        try Task.checkCancellation()
        var schedule = Schedule()
        while true {
            do {
                return try await watch(pending, of: transaction, schedule: &schedule)
            } catch {
                try Task.checkCancellation()
                guard (error as? RPCError)?.isRecoverable == true else { throw error }
            }
            try await clock.sleep(for: schedule.backoff.next())
        }
    }

    /// Subscribes once, then follows the landing and roots until the outcome settles or the connection fails.
    ///
    /// - Parameters:
    ///   - pending: The transaction's pending outcome.
    ///   - transaction: The sent transaction.
    ///   - schedule: The checks and reconnection wait that every connection shares.
    /// - Returns: The settled outcome.
    /// - Throws: A subscription, RPC, stall, lost connection, or cancellation error.
    private func watch(_ pending: TransactionOutcome, of transaction: Transaction,
                       schedule: inout Schedule) async throws -> TransactionOutcome {
        let events = try await rpc.events(for: pending.signature)
        let checksExpiry = schedule.expiry == nil
        async let catchUpRead = rpc.send(GetSignatureStatuses(signatures: [pending.signature]))
        async let epochRead = checksExpiry ? rpc.send(GetEpochInfo()) : nil
        let catchUp = try await catchUpRead
        if let outcome = settle(catchUp, for: pending, of: transaction, at: schedule.root, schedule: &schedule) {
            return outcome
        }
        if let epoch = try await epochRead { record(epoch, for: pending, at: schedule.root, schedule: &schedule) }
        if checksExpiry, schedule.expiry != nil {
            if let outcome = settle(catchUp, for: pending, of: transaction, at: schedule.root, schedule: &schedule) {
                return outcome
            }
            if let outcome = try await check(pending, of: transaction, at: schedule.root, schedule: &schedule) {
                return outcome
            }
        }
        schedule.backoff.reset()
        while let event = try await next(from: events) {
            try Task.checkCancellation()
            switch event {
            case .landed(let slot, let error):
                return pending.landed(at: slot, error: error, in: transaction)
            case .rooted(let root):
                schedule.root = root
                guard root >= schedule.nextCheck else { continue }
                if let outcome = try await check(pending, of: transaction, at: root, schedule: &schedule) {
                    return outcome
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
    ///   - pending: The transaction's pending outcome.
    ///   - transaction: The sent transaction.
    ///   - root: The newest root.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: The outcome once a status read settles it, or `nil` to keep watching.
    /// - Throws: An RPC or cancellation error.
    private func check(_ pending: TransactionOutcome, of transaction: Transaction, at root: UInt64,
                       schedule: inout Schedule) async throws -> TransactionOutcome? {
        guard try await hasExpired(pending, at: root, schedule: &schedule) else { return nil }
        let response = try await rpc.send(GetSignatureStatuses(signatures: [pending.signature]))
        return settle(response, for: pending, of: transaction, at: root, schedule: &schedule)
    }

    /// Returns the outcome that a status read proves, or schedules the next check.
    ///
    /// - Parameters:
    ///   - response: The transaction's status read.
    ///   - pending: The transaction's pending outcome.
    ///   - transaction: The sent transaction.
    ///   - root: The newest root, or `0` before the first one.
    ///   - schedule: The expiry slot, once read, and the next check.
    /// - Returns: The outcome, or `nil` to keep watching.
    private func settle(_ response: GetSignatureStatuses.Response, for pending: TransactionOutcome,
                        of transaction: Transaction, at root: UInt64, schedule: inout Schedule) -> TransactionOutcome? {
        let status = response.value[0]
        if let status, status.confirmationStatus == .finalized {
            return pending.landed(at: status.slot, error: status.error, in: transaction)
        }
        guard let expiry = schedule.expiry else { return nil }
        let context = response.context.slot
        if context >= expiry, status == nil {
            return pending.settled(.dropped)
        }
        schedule.nextCheck = Self.sum(max(root, expiry), context < expiry ? expiry - context : 1)
        return nil
    }

    /// Returns whether the blockhash expired at finalized commitment, reading it unless an earlier read found it.
    ///
    /// - Parameters:
    ///   - pending: The transaction's pending outcome.
    ///   - root: The newest root.
    ///   - schedule: The next check and, once read, the expiry slot.
    /// - Returns: Whether a finalized block height above the last valid one was read.
    /// - Throws: A read or cancellation error.
    private func hasExpired(_ pending: TransactionOutcome, at root: UInt64,
                            schedule: inout Schedule) async throws -> Bool {
        if schedule.expiry != nil { return true }
        record(try await rpc.send(GetEpochInfo()), for: pending, at: root, schedule: &schedule)
        return schedule.expiry != nil
    }

    /// Records the expiry slot once a finalized block height passes the last valid one, or schedules the next check.
    ///
    /// - Parameters:
    ///   - epoch: A finalized epoch read.
    ///   - pending: The transaction's pending outcome.
    ///   - root: The newest root.
    ///   - schedule: The next check or, once the blockhash has expired, the expiry slot.
    private func record(_ epoch: GetEpochInfo.Response, for pending: TransactionOutcome, at root: UInt64,
                        schedule: inout Schedule) {
        guard epoch.blockHeight > pending.lastValidBlockHeight else {
            let remaining = pending.lastValidBlockHeight - epoch.blockHeight
            schedule.nextCheck = Self.sum(max(root, epoch.absoluteSlot), Self.sum(remaining, 1))
            return
        }
        schedule.expiry = epoch.absoluteSlot
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
        /// The wait before the next reconnection.
        var backoff = Backoff.reconnection
    }
}

private nonisolated extension TransactionOutcome {
    /// Returns the succeeded or failed outcome of a landing.
    ///
    /// - Parameters:
    ///   - slot: The slot that the transaction landed in.
    ///   - error: The transaction's error, or `nil` if it ran.
    ///   - transaction: The sent transaction.
    /// - Returns: The settled outcome.
    func landed(at slot: UInt64, error: TransactionError?, in transaction: Transaction) -> TransactionOutcome {
        settled(error.map { .failed(slot: slot, ExecutionError($0, in: transaction)) } ?? .succeeded(slot: slot))
    }
}
