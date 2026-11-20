import Foundation
import Observation
import RPC
import Storage
import Transactions

/// A store that sends and watches the app's transactions and keeps their records.
@MainActor
@Observable
final class TransactionStore: Erasable {
    /// The most records kept for each account on each network.
    nonisolated static let recordLimit = 100

    private let storage: (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]>
    private let makeCoordinator: (Network) throws -> any TransactionCoordinating
    @ObservationIgnored private let pendingKeys: PersistentValue<Set<TransactionRecord.Key>>
    @ObservationIgnored private var coordinators: [Network: any TransactionCoordinating] = [:]
    @ObservationIgnored private var entries: [TransactionRecord.Key: Entry] = [:]

    /// Creates a store that keeps its records and pending index in memory and saves them when their storage works.
    ///
    /// - Parameters:
    ///   - storage: Returns the storage of an account's records on a network.
    ///   - pending: The storage of the keys with pending records.
    ///   - coordinators: Creates a network's transaction coordinator.
    init(storage: @escaping (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]>,
         pending: any ValueStoring<Set<TransactionRecord.Key>>,
         coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.storage = { MemoryItem(savingTo: storage($0)) }
        pendingKeys = PersistentValue(storage: MemoryItem(savingTo: pending), empty: [])
        makeCoordinator = coordinators
    }

    /// Creates a store whose files are in a directory.
    ///
    /// - Parameters:
    ///   - directory: The directory of the records and the pending index.
    ///   - coordinators: Creates a network's transaction coordinator.
    convenience init(directory: URL, coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.init(storage: Self.files(in: directory), pending: Self.pendingIndex(in: directory),
                  coordinators: coordinators)
    }

    /// Returns the storage of each key's records, at `<network>/<account>.json` in a directory.
    ///
    /// - Parameter directory: The directory of the records.
    /// - Returns: The storage of a key's records.
    nonisolated static func files(in directory: URL)
        -> @Sendable (TransactionRecord.Key) -> any ValueStoring<[TransactionRecord]> {
        { key in
            FileItem(url: directory.appending(path: key.network.rawValue, directoryHint: .isDirectory)
                         .appending(path: "\(key.account.uuidString).json"),
                     coding: .json([TransactionRecord].self, version: 1, outdated: []))
        }
    }

    /// Returns the storage of the pending index, at `pending.json` in a directory.
    ///
    /// - Parameter directory: The directory of the pending index.
    /// - Returns: The pending index's storage.
    nonisolated static func pendingIndex(in directory: URL) -> any ValueStoring<Set<TransactionRecord.Key>> {
        FileItem(url: directory.appending(path: "pending.json"),
                 coding: .json(Set<TransactionRecord.Key>.self, version: 1, outdated: []))
    }

    /// Returns a network's coordinator, creating it on the first request.
    ///
    /// - Parameter network: The network to send on.
    /// - Returns: The network's coordinator.
    /// - Throws: An error if the coordinator can't be created.
    func coordinator(for network: Network) throws -> any TransactionCoordinating {
        if let coordinator = coordinators[network] { return coordinator }
        let coordinator = try makeCoordinator(network)
        coordinators[network] = coordinator
        return coordinator
    }

    /// Reads an account's records on a network, unless they were already read.
    ///
    /// - Parameter key: The account and network.
    func load(_ key: TransactionRecord.Key) async {
        await entry(for: key).records.load()
    }

    /// Returns whether an account's records on a network were read.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: The records' read phase.
    func phase(for key: TransactionRecord.Key) -> PersistentValuePhase {
        entry(for: key).records.phase
    }

    /// Returns an account's records on a network, newest first.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: At most ``recordLimit`` records, or none before they're read.
    func records(for key: TransactionRecord.Key) -> [TransactionRecord] {
        entry(for: key).records.value
    }

    /// Returns one of an account's records on a network.
    ///
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The record, or `nil` if it isn't kept or read.
    func record(_ id: TransactionRecord.ID, for key: TransactionRecord.Key) -> TransactionRecord? {
        records(for: key).first { $0.id == id }
    }

    /// Returns how many of an account's transactions on a network settled since launch.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: The number of settled transactions.
    func settledCount(for key: TransactionRecord.Key) -> Int {
        entry(for: key).settledCount
    }

    /// Signs and sends an approved transaction, records it as pending, and starts watching it.
    ///
    /// - Parameters:
    ///   - simulation: The approved simulation from this store's coordinator for its network.
    ///   - kind: What the transaction does.
    ///   - account: The account that signs and pays.
    ///   - settling: What finishes the transaction's work once its outcome is found, or `nil` for nothing.
    /// - Returns: The pending record.
    /// - Throws: `CancellationError` if the person cancels authentication, the coordinator's error if nothing was
    ///   sent, or a storage error.
    func send(_ simulation: Simulation, as kind: TransactionRecord.Kind, from account: Account,
              settling: (any TransactionSettling)? = nil) async throws -> TransactionRecord {
        let coordinator = try coordinator(for: simulation.network)
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
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The settled status.
    /// - Throws: ``TransactionStoreError/missingRecord`` if the record isn't kept, `CancellationError` if the caller
    ///   is cancelled, or the watch's error.
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

    /// Starts watching every pending record that has no watch.
    ///
    /// - Parameter replacingFailedWatches: Whether to restart watches that ended with an error that no caller read.
    func resume(replacingFailedWatches: Bool = false) async {
        await pendingKeys.load()
        for key in pendingKeys.value {
            let entry = entry(for: key)
            if entry.records.phase != .loaded { await entry.records.load() }
            guard entry.records.phase == .loaded, !entry.isErased else { continue }
            for record in entry.records.value where record.status == .pending {
                guard let watch = entry.watches[record.id] else {
                    startWatch(of: record, in: entry)
                    continue
                }
                if replacingFailedWatches, watch.isFinished { startWatch(of: record, in: entry) }
            }
            await index(key, in: entry)
        }
    }

    func erase() async throws {
        let entries = Array(entries.values)
        for entry in entries { stop(entry) }
        for entry in entries { try await entry.records.erase() }
        try await pendingKeys.erase()
    }

    /// Stops an account's watches and deletes its records on every network.
    ///
    /// - Parameter account: The identifier of the account.
    /// - Throws: A storage error from the first records that can't be deleted.
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

    /// Returns a key's entry, creating it on first use.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: The key's entry.
    private func entry(for key: TransactionRecord.Key) -> Entry {
        if let entry = entries[key] { return entry }
        let entry = Entry(storage: storage(key))
        entries[key] = entry
        return entry
    }

    /// Stops a key's watches for good and forgets the settlings that didn't run.
    ///
    /// - Parameter entry: The key's entry.
    private func stop(_ entry: Entry) {
        entry.isErased = true
        for watch in entry.watches.values { watch.cancel() }
        entry.watches = [:]
        entry.settlings = [:]
    }

    /// Saves a pending record as the newest, dropping the oldest beyond the limit, and starts watching it.
    ///
    /// - Parameters:
    ///   - record: The pending record.
    ///   - settling: What finishes the transaction's work once its outcome is found, or `nil` for nothing.
    /// - Returns: The saved record.
    /// - Throws: A storage error.
    private func save(_ record: TransactionRecord, settling: (any TransactionSettling)?) async throws
        -> TransactionRecord {
        let entry = entry(for: record.key)
        if entry.records.phase != .loaded { await entry.records.load() }
        try? await pendingKeys.update { $0.insert(record.key) }
        try await update(entry, of: record.key) { records in
            records = Array(([record] + records).prefix(Self.recordLimit))
        }
        entry.settlings[record.id] = settling
        startWatch(of: record, in: entry)
        return record
    }

    /// Starts watching a pending record.
    ///
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

    /// Changes and saves a key's records, then updates the pending index.
    ///
    /// - Parameters:
    ///   - entry: The key's entry, whose records were read.
    ///   - key: The account and network.
    ///   - change: Changes the records.
    /// - Throws: A storage error from the records.
    private func update(_ entry: Entry, of key: TransactionRecord.Key,
                        _ change: @escaping @Sendable (inout [TransactionRecord]) -> Void) async throws {
        try await entry.records.update(change)
        await index(key, in: entry)
    }

    /// Lists a key in the pending index while its records include a pending record, and removes it once none is left.
    ///
    /// - Parameters:
    ///   - key: The account and network.
    ///   - entry: The key's entry, whose records were read.
    private func index(_ key: TransactionRecord.Key, in entry: Entry) async {
        await pendingKeys.load()
        let isPending = entry.records.value.contains { $0.status == .pending }
        guard pendingKeys.value.contains(key) != isPending else { return }
        try? await pendingKeys.update { keys in
            if isPending { keys.insert(key) } else { keys.remove(key) }
        }
    }

    /// Waits for a watch's result, then forgets the watch once it ended.
    ///
    /// - Parameters:
    ///   - watch: The record's watch.
    ///   - id: The record's signature.
    ///   - entry: The record's key's entry.
    /// - Returns: The settled status.
    /// - Throws: `CancellationError` if the caller is cancelled, or the watch's error.
    private func result(of watch: Watch, for id: TransactionRecord.ID, in entry: Entry) async throws
        -> TransactionRecord.Status {
        defer { if watch.isFinished, entry.watches[id] === watch { entry.watches[id] = nil } }
        return try await watch.value()
    }

    /// Watches a pending record's transaction until it settles, saves the outcome, and runs its settling once.
    ///
    /// - Parameters:
    ///   - record: The pending record.
    ///   - entry: The record's key's entry.
    /// - Returns: The settled status.
    /// - Throws: The coordinator's creation or watch error, or a storage error.
    private func settle(_ record: TransactionRecord, in entry: Entry) async throws -> TransactionRecord.Status {
        let confirmation = try await coordinator(for: record.key.network).confirm(record.submission)
        try Task.checkCancellation()
        let status = TransactionRecord.Status(confirmation.outcome)
        let settled = Date.now
        try await update(entry, of: record.key) { records in
            guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
            records[index].status = status
            records[index].settled = settled
        }
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
        @ObservationIgnored var isErased = false
        /// The watch of each pending record, kept after it ends until a caller reads its result.
        @ObservationIgnored var watches: [TransactionRecord.ID: Watch] = [:]
        @ObservationIgnored var settlings: [TransactionRecord.ID: any TransactionSettling] = [:]

        /// Creates an entry without reading its records.
        ///
        /// - Parameter storage: The storage of the records.
        init(storage: any ValueStoring<[TransactionRecord]>) {
            records = PersistentValue(storage: storage, empty: [])
        }
    }

    /// One watch of a pending record, which callers can join and which keeps its result after it ends.
    @MainActor
    fileprivate final class Watch {
        private var task: Task<Void, Never>?
        private var result: Result<TransactionRecord.Status, any Error>?
        private var waiters: [UUID: CheckedContinuation<TransactionRecord.Status, any Error>] = [:]

        var isFinished: Bool { result != nil }

        /// Runs the watch in its own task, then hands its result to every caller that waits.
        ///
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

        /// Waits for the watch's result.
        ///
        /// - Returns: The settled status.
        /// - Throws: `CancellationError` if the caller is cancelled, or the watch's error.
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

        /// Cancels the watch.
        func cancel() {
            task?.cancel()
        }

        /// Keeps the watch's result and hands it to every caller that waits.
        ///
        /// - Parameter result: The settled status, or the watch's error.
        private func finish(with result: Result<TransactionRecord.Status, any Error>) {
            self.result = result
            let waiters = waiters
            self.waiters = [:]
            for waiter in waiters.values { waiter.resume(with: result) }
        }

        /// Ends one caller's wait with a cancellation error.
        ///
        /// - Parameter id: The identifier of the caller's wait.
        private func stopWaiting(_ id: UUID) {
            waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
    }
}
