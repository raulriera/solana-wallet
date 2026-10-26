import Foundation
import Observation
import RPC
import Storage
import Transactions

/// Sends and watches every transaction that the app sends, and keeps their records, which every window shares.
///
/// Records are kept per account and network, newest first, and only the latest 200 of each. The store reads a key's
/// records on first use and creates a network's transaction coordinator when something first sends or simulates on it.
/// Sending and watching run in tasks that the store owns, so a review that closes or a caller that's cancelled stops
/// only its own wait: the transaction is still delivered, recorded, and watched until it settles. A pending index lists
/// the keys with pending records, so ``resume()`` watches them again after a relaunch without reading every key's
/// records.
@MainActor
@Observable
final class TransactionStore {
    /// The most records kept for each account on each network.
    nonisolated static let recordLimit = 200

    private let storage: (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]>
    private let makeCoordinator: (Network) throws -> any TransactionCoordinating
    /// The keys whose records include a pending record, and maybe keys whose records all settled since.
    @ObservationIgnored private let pendingKeys: PersistentValue<Set<TransactionRecord.Key>>
    @ObservationIgnored private var coordinators: [Network: any TransactionCoordinating] = [:]
    @ObservationIgnored private var entries: [TransactionRecord.Key: Entry] = [:]

    /// Connects to the records' storage, the pending index, and the networks' coordinators, without reading or
    /// creating any.
    /// - Parameters:
    ///   - storage: Returns the storage that keeps an account's records on a network.
    ///   - pending: The storage of the pending index, which lists the keys with pending records.
    ///   - coordinators: Creates a network's transaction coordinator.
    init(storage: @escaping (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]>,
         pending: any ValueStoring<Set<TransactionRecord.Key>>,
         coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.storage = storage
        pendingKeys = PersistentValue(storage: pending, empty: [])
        makeCoordinator = coordinators
    }

    /// Connects to the Transactions files in a directory and the networks' coordinators, without reading or creating
    /// any.
    /// - Parameters:
    ///   - directory: The directory that keeps each key's records and the pending index.
    ///   - coordinators: Creates a network's transaction coordinator.
    convenience init(directory: URL, coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.init(storage: Self.files(in: directory), pending: Self.pendingIndex(in: directory),
                  coordinators: coordinators)
    }

    /// The files that keep each account's records on each network, at `<network>/<account>.json` in a directory.
    /// - Parameter directory: The directory that keeps the Transactions files.
    /// - Returns: The storage of each key's records, which isn't created or read yet.
    nonisolated static func files(in directory: URL)
        -> @Sendable (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]> {
        { key in
            FileItem(url: directory.appending(path: key.network.rawValue, directoryHint: .isDirectory)
                         .appending(path: "\(key.account.uuidString).json"),
                     coding: .json([TransactionRecord].self))
        }
    }

    /// The file that keeps the pending index, at `pending.json` in a directory.
    /// - Parameter directory: The directory that keeps the Transactions files.
    /// - Returns: The pending index's storage, which isn't created or read yet.
    nonisolated static func pendingIndex(in directory: URL) -> any ValueStoring<Set<TransactionRecord.Key>> {
        FileItem(url: directory.appending(path: "pending.json"), coding: .json(Set<TransactionRecord.Key>.self))
    }

    /// Returns a network's coordinator, which simulates the transactions that the store sends, creating it on the
    /// first request.
    /// - Parameter network: The network to send on.
    /// - Returns: The coordinator that every window on the network shares.
    /// - Throws: The error of creating the coordinator; the next request tries again.
    func coordinator(for network: Network) throws -> any TransactionCoordinating {
        if let coordinator = coordinators[network] { return coordinator }
        let coordinator = try makeCoordinator(network)
        coordinators[network] = coordinator
        return coordinator
    }

    /// Reads an account's records on a network, unless they were already read, and returns once the changes made
    /// before this call are saved or undone.
    /// - Parameter key: The account and network.
    func load(_ key: TransactionRecord.Key) async {
        await entry(for: key).records.load()
    }

    /// Whether an account's records on a network were read.
    /// - Parameter key: The account and network.
    /// - Returns: The records' read phase.
    func phase(for key: TransactionRecord.Key) -> PersistentValuePhase {
        entry(for: key).records.phase
    }

    /// An account's records on a network, newest first.
    /// - Parameter key: The account and network.
    /// - Returns: At most ``recordLimit`` records, or none before they're read.
    func records(for key: TransactionRecord.Key) -> [TransactionRecord] {
        entry(for: key).records.value
    }

    /// One of an account's records on a network.
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The record, or `nil` when it isn't kept or isn't read yet.
    func record(_ id: TransactionRecord.ID, for key: TransactionRecord.Key) -> TransactionRecord? {
        records(for: key).first { $0.id == id }
    }

    /// The latest succeeded payment to each recipient, across several accounts' records.
    /// - Parameters:
    ///   - keys: The accounts and networks whose payments count.
    ///   - limit: The most payments to return.
    /// - Returns: One payment per recipient, the latest to land first.
    func recentPayments(for keys: [TransactionRecord.Key], limit: Int) -> [TransactionRecord] {
        let payments = keys.flatMap(records(for:))
            .filter { $0.status == .succeeded }
            .sorted { ($0.settled ?? $0.created) > ($1.settled ?? $1.created) }
        var recipients: Set<Address> = []
        var latest: [TransactionRecord] = []
        for payment in payments where latest.count < limit {
            guard let recipient = payment.kind.recipient, recipients.insert(recipient).inserted else { continue }
            latest.append(payment)
        }
        return latest
    }

    /// How many of an account's transactions on a network settled since launch; it increases after each settles and
    /// its settling runs.
    /// - Parameter key: The account and network.
    /// - Returns: The number of settled transactions.
    func settledCount(for key: TransactionRecord.Key) -> Int {
        entry(for: key).settledCount
    }

    /// Signs and sends an approved transaction, records it as pending, and starts watching it.
    ///
    /// Sending runs in a task that the store owns, so cancelling the caller doesn't stop it. A transaction whose
    /// delivery is unknown after signing is still recorded and watched, since it may land.
    /// - Parameters:
    ///   - simulation: The review that the person approved, from this store's coordinator for its network.
    ///   - kind: What the transaction does.
    ///   - account: The account that signs and pays.
    ///   - settling: What finishes the transaction's work once its outcome is found, if anything.
    /// - Returns: The pending record.
    /// - Throws: `CancellationError` when the person cancels authentication, the coordinator's error when nothing was
    ///   signed or sent, or a storage error after sending.
    func send(_ simulation: Simulation, as kind: TransactionRecord.Kind, from account: Account,
              settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        let coordinator = try coordinator(for: simulation.network)
        // Sending needs nothing from the main actor; saving the record hops back to it.
        let delivery = Task { @concurrent in
            let submission: Submission
            do {
                submission = try await coordinator.submit(simulation)
            } catch let error as DeliveryError {
                submission = error.submission
            }
            return try await self.save(TransactionRecord(kind, from: account.id, submission: submission, created: .now),
                                  settling: settling)
        }
        return try await delivery.value
    }

    /// Waits for a pending record's outcome, joining its watch or starting one.
    ///
    /// The watch runs in a task that the store owns: cancelling the caller stops only its wait. Once the outcome is
    /// found, the watch saves it, runs the transaction's settling once, then increases ``settledCount(for:)``. A watch
    /// that ended keeps its result for the next caller, even when no caller waited, so an error is never skipped: after
    /// a watch error the record stays pending, the next caller receives the error, and watching again starts a new
    /// watch. Only ``resume()`` replaces a watch whose error no caller read.
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The settled status; a settled record returns its status at once.
    /// - Throws: ``TransactionStoreError/missingRecord`` when the record isn't kept, `CancellationError` when the
    ///   caller is cancelled, or the watch's error, such as a ``DeliveryError`` or a storage error.
    func watch(_ id: TransactionRecord.ID, for key: TransactionRecord.Key) async throws -> TransactionRecord.Status {
        let entry = entry(for: key)
        if let watch = entry.watches[id] { return try await result(of: watch, for: id, in: entry) }
        if entry.records.phase != .loaded { await entry.records.load() }
        guard let record = entry.records.value.first(where: { $0.id == id }) else {
            throw TransactionStoreError.missingRecord
        }
        guard record.status == .pending else { return record.status }
        return try await result(of: startWatch(of: record, in: entry), for: id, in: entry)
    }

    /// Watches every pending record that has no watch, as after a relaunch.
    ///
    /// It reads only the records of the keys in the pending index, so a launch reads no key whose records all settled.
    /// Calling it again while the watches run starts none. A watch that ended with an error keeps it for the next
    /// caller, since errors such as a rate limit aren't retried on their own; only a change that may fix them, such as
    /// a new provider connection, replaces it.
    /// - Parameter replacingFailedWatches: Whether watches that ended with an error that no caller read start again.
    func resume(replacingFailedWatches: Bool = false) async {
        await pendingKeys.load()
        for key in pendingKeys.value {
            let entry = entry(for: key)
            if entry.records.phase != .loaded { await entry.records.load() }
            // An erase during the read stopped the key for good, though the read may still show its records.
            guard entry.records.phase == .loaded, !entry.isErased else { continue }
            for record in entry.records.value where record.status == .pending {
                guard let watch = entry.watches[record.id] else {
                    startWatch(of: record, in: entry)
                    continue
                }
                if replacingFailedWatches, watch.isFinished { startWatch(of: record, in: entry) }
            }
            // A key whose records all settled leaves the index, as after the app stopped before the index was saved.
            await index(key, in: entry)
        }
    }

    /// Stops every watch for good, then deletes every record that the store read and the pending index, so every window
    /// forgets them.
    ///
    /// Settlings that didn't run are forgotten; the private balances' indexer sync still finds their transactions.
    /// - Throws: A storage error from the first records that can't be deleted, or from the pending index.
    func erase() async throws {
        let entries = Array(entries.values)
        for entry in entries { stop(entry) }
        for entry in entries { try await entry.records.erase() }
        try await pendingKeys.erase()
    }

    /// Stops an account's watches on every network, then deletes its records on every network, read or not, and
    /// forgets them, as after the account is deleted.
    ///
    /// Settlings that didn't run are forgotten; the private balances' indexer sync still finds their transactions.
    /// - Parameter account: The identifier of the account.
    /// - Throws: A storage error from the first records that can't be deleted, after which the records after them and
    ///   the account's keys in the pending index stay.
    func erase(account: UUID) async throws {
        let keys = Network.allCases.map { TransactionRecord.Key(account: account, network: $0) }
        let entries = keys.map(entry(for:))
        for entry in entries { stop(entry) }
        for entry in entries { try await entry.records.erase() }
        for key in keys { self.entries[key] = nil }
        await pendingKeys.load()
        guard pendingKeys.value.contains(where: { $0.account == account }) else { return }
        try await pendingKeys.update { $0 = $0.filter { $0.account != account } }
    }

    /// Returns a key's records, settled count, and watches, creating them on first use without reading anything.
    /// - Parameter key: The account and network.
    /// - Returns: The key's entry.
    private func entry(for key: TransactionRecord.Key) -> Entry {
        if let entry = entries[key] { return entry }
        let entry = Entry(storage: storage(key))
        entries[key] = entry
        return entry
    }

    /// Stops a key's watches for good, as before its records are erased, and forgets the settlings that didn't run.
    /// - Parameter entry: The key's entry.
    private func stop(_ entry: Entry) {
        entry.isErased = true
        for watch in entry.watches.values { watch.cancel() }
        entry.watches = [:]
        entry.settlings = [:]
    }

    /// Saves a sent transaction's pending record as the newest, forgetting the oldest beyond the limit, and starts
    /// watching it.
    /// - Parameters:
    ///   - record: The pending record.
    ///   - settling: What finishes the transaction's work once its outcome is found, if anything.
    /// - Returns: The saved record.
    /// - Throws: A storage error, after which the record isn't kept or watched.
    private func save(_ record: TransactionRecord, settling: (any TransactionSettling)?) async throws
        -> TransactionRecord {
        let entry = entry(for: record.key)
        if entry.records.phase != .loaded { await entry.records.load() }
        // The key joins the index before the record is saved, so a relaunch after the save always resumes it.
        try? await pendingKeys.update { $0.insert(record.key) }
        try await update(entry, of: record.key) { records in
            records = Array(([record] + records).prefix(Self.recordLimit))
        }
        entry.settlings[record.id] = settling
        startWatch(of: record, in: entry)
        return record
    }

    /// Starts the store-owned watch of a pending record, which stays in the key's watches until a caller reads its
    /// result.
    /// - Parameters:
    ///   - record: The pending record.
    ///   - entry: The record's key's entry.
    /// - Returns: The running watch.
    @discardableResult
    private func startWatch(of record: TransactionRecord, in entry: Entry) -> Watch {
        let watch = Watch()
        entry.watches[record.id] = watch
        watch.start { [self] in try await settle(record, in: entry) }
        return watch
    }

    /// Changes a key's records and saves them, then updates the pending index, so the index always follows the records.
    /// - Parameters:
    ///   - entry: The key's entry, whose records were read.
    ///   - key: The account and network.
    ///   - change: Changes the records.
    /// - Throws: A storage error from the records, which leaves the index as it is.
    private func update(_ entry: Entry, of key: TransactionRecord.Key,
                        _ change: @escaping @Sendable (inout [TransactionRecord]) -> Void) async throws {
        try await entry.records.update(change)
        // A change to the same key meanwhile, such as a watch that settled, may have changed the index.
        await index(key, in: entry)
    }

    /// Lists a key in the pending index while its records include a pending record, and removes it once none is left.
    ///
    /// An index that can't be read or saved is left as it is, as a storage failure of the records is: a pending record
    /// of a key that the index misses isn't resumed after a relaunch until a caller watches it.
    /// - Parameters:
    ///   - key: The account and network.
    ///   - entry: The key's entry, whose records were read.
    private func index(_ key: TransactionRecord.Key, in entry: Entry) async {
        await pendingKeys.load()
        // Deciding after the wait, with no wait before the change, orders the change after every change before it.
        let isPending = entry.records.value.contains { $0.status == .pending }
        guard pendingKeys.value.contains(key) != isPending else { return }
        try? await pendingKeys.update { keys in
            if isPending { keys.insert(key) } else { keys.remove(key) }
        }
    }

    /// Waits for a watch's result, then forgets the watch once it ended, so the next caller reads the saved status or
    /// starts a new watch.
    /// - Parameters:
    ///   - watch: The record's watch.
    ///   - id: The record's signature.
    ///   - entry: The record's key's entry.
    /// - Returns: The settled status.
    /// - Throws: `CancellationError` when the caller is cancelled, or the watch's error.
    private func result(of watch: Watch, for id: TransactionRecord.ID, in entry: Entry) async throws
        -> TransactionRecord.Status {
        defer { if watch.isFinished, entry.watches[id] === watch { entry.watches[id] = nil } }
        return try await watch.value()
    }

    /// Watches a pending record's transaction until it settles, saves the outcome, runs the settling once, and then
    /// counts the settled transaction.
    /// - Parameters:
    ///   - record: The pending record.
    ///   - entry: The record's key's entry.
    /// - Returns: The settled status.
    /// - Throws: The coordinator's creation or watch error, or a storage error; the record stays pending.
    private func settle(_ record: TransactionRecord, in entry: Entry) async throws -> TransactionRecord.Status {
        let confirmation = try await coordinator(for: record.key.network).confirm(record.submission)
        // A stopped watch saves nothing, so an erase that stopped it doesn't see its records written again.
        try Task.checkCancellation()
        let status = TransactionRecord.Status(confirmation.outcome)
        let settled = Date.now
        try await update(entry, of: record.key) { records in
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
            records[index].status = status
            records[index].settled = settled
        }
        // An erase while the outcome was saved stopped the watch, so the forgotten transaction isn't counted.
        try Task.checkCancellation()
        if let settling = entry.settlings.removeValue(forKey: record.id) { await settling.settle(confirmation) }
        entry.settledCount += 1
        return status
    }

    /// One account's records on one network, its settled count, and the watches and settlings of its pending records.
    @MainActor
    @Observable
    fileprivate final class Entry {
        /// The records, newest first.
        let records: PersistentValue<[TransactionRecord]>
        /// How many of the key's transactions settled since launch.
        var settledCount = 0
        /// Whether the key's records were erased, after which none of its watches starts again.
        @ObservationIgnored var isErased = false
        /// The watch of each pending record, kept after it ends until a caller reads its result.
        @ObservationIgnored var watches: [TransactionRecord.ID: Watch] = [:]
        /// What finishes each pending transaction's work once its outcome is found.
        @ObservationIgnored var settlings: [TransactionRecord.ID: any TransactionSettling] = [:]

        /// Connects to the storage of the key's records, without reading it.
        /// - Parameter storage: The storage that keeps the records.
        init(storage: any ValueStoring<[TransactionRecord]>) {
            records = PersistentValue(storage: storage, empty: [])
        }
    }

    /// One watch of a pending record, which runs in a task that the store owns; callers join it and stop waiting
    /// without stopping it, and the result stays for callers that arrive after it ended.
    @MainActor
    fileprivate final class Watch {
        private var task: Task<Void, Never>?
        private var result: Result<TransactionRecord.Status, any Error>?
        private var waiters: [UUID: CheckedContinuation<TransactionRecord.Status, any Error>] = [:]

        /// Whether the watch ended with a status or an error.
        var isFinished: Bool { result != nil }

        /// Runs the watch in its own task, then hands its result to every caller that waits.
        /// - Parameter operation: Watches the record until it settles and saves the outcome.
        func start(_ operation: @escaping @MainActor () async throws -> TransactionRecord.Status) {
            task = Task {
                let result: Result<TransactionRecord.Status, any Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                finish(with: result)
            }
        }

        /// Waits for the watch's result; cancelling the caller ends only its wait.
        /// - Returns: The settled status.
        /// - Throws: `CancellationError` when the caller is cancelled, or the watch's error.
        func value() async throws -> TransactionRecord.Status {
            let id = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if let result {
                        continuation.resume(with: result)
                    } else if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters[id] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor in self.stopWaiting(id) }
            }
        }

        /// Stops the watch; callers that wait receive its cancellation error.
        func cancel() {
            task?.cancel()
        }

        /// Keeps the watch's result and hands it to every caller that waits.
        /// - Parameter result: The settled status, or the watch's error.
        private func finish(with result: Result<TransactionRecord.Status, any Error>) {
            self.result = result
            let waiters = waiters
            self.waiters = [:]
            for waiter in waiters.values { waiter.resume(with: result) }
        }

        /// Ends one caller's wait with a cancellation error, unless the watch already finished.
        /// - Parameter id: The caller's wait.
        private func stopWaiting(_ id: UUID) {
            waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
    }
}
