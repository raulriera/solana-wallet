import Foundation
import Observation
import RPC
import Storage
import Transactions

/// A store that sends and watches the app's transactions.
///
/// The store keeps each transaction's record in memory for as long as the app runs. It saves only the pending
/// records, so that the next launch can watch them again; a file that can't be read or written never fails a send.
@MainActor
@Observable
final class TransactionStore: Erasable {
    private let storage: any ValueStoring<[TransactionRecord]>
    private let makeCoordinator: (Network) throws -> any TransactionCoordinating
    @ObservationIgnored private var coordinators: [Network: any TransactionCoordinating] = [:]
    @ObservationIgnored private var entries: [TransactionRecord.Key: Entry] = [:]
    /// The one read of the saved pending records.
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// Creates a store without reading the saved pending records.
    ///
    /// - Parameters:
    ///   - storage: The storage of the pending records.
    ///   - coordinators: Creates a network's transaction coordinator.
    init(storage: any ValueStoring<[TransactionRecord]>,
         coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.storage = storage
        makeCoordinator = coordinators
    }

    /// Creates a store whose file is in a directory.
    ///
    /// - Parameters:
    ///   - directory: The directory of the pending records.
    ///   - coordinators: Creates a network's transaction coordinator.
    convenience init(directory: URL, coordinators: @escaping (Network) throws -> any TransactionCoordinating) {
        self.init(storage: Self.file(in: directory), coordinators: coordinators)
    }

    /// Returns the storage of the pending records, at `pending.json` in a directory.
    ///
    /// - Parameter directory: The directory of the pending records.
    /// - Returns: The pending records' storage.
    nonisolated static func file(in directory: URL) -> any ValueStoring<[TransactionRecord]> {
        FileItem(url: directory.appending(path: "pending.json"),
                 coding: .json([TransactionRecord].self, version: 1, unusable: .replaced(with: [])))
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

    /// Reads the saved pending records, unless they were already read.
    func load() async {
        if reading == nil {
            reading = Task { [storage] in
                for record in (try? await storage.load()) ?? [] where self.record(record.id, for: record.key) == nil {
                    self.entry(for: record.key).records.append(record)
                }
            }
        }
        await reading?.value
    }

    /// Returns an account's records on a network: the pending ones, and those that settled since launch.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: The records, newest first.
    func records(for key: TransactionRecord.Key) -> [TransactionRecord] {
        entry(for: key).records
    }

    /// Returns one of an account's records on a network.
    ///
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The record, or `nil` if it isn't kept.
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
    ///   - settling: What runs the transaction's remaining work once it settles, or `nil` for nothing.
    ///   - coordinator: The coordinator that signs and sends, which accepts the simulation, or `nil` for this
    ///     store's coordinator for the simulation's network.
    /// - Returns: The pending record.
    /// - Throws: `CancellationError` if the person cancels authentication, or the coordinator's error if nothing was
    ///   sent.
    func send(_ simulation: Simulation, as kind: TransactionRecord.Kind, from account: Account,
              settling: (any TransactionSettling)? = nil,
              using coordinator: (any TransactionCoordinating)? = nil) async throws -> TransactionRecord {
        let coordinator = try coordinator ?? self.coordinator(for: simulation.network)
        let delivery = Task { @concurrent in
            let outcome = try await coordinator.submit(simulation)
            return await self.track(TransactionRecord(kind, from: account.id, outcome: outcome), settling: settling)
        }
        return try await delivery.value
    }

    /// Waits for a record to settle, joining its watch or starting one; a settled record returns at once.
    ///
    /// - Parameters:
    ///   - id: The record's signature.
    ///   - key: The account and network.
    /// - Returns: The transaction's settled outcome.
    /// - Throws: ``TransactionStoreError/missingRecord`` if the record isn't kept, `CancellationError` if the caller
    ///   is cancelled, or the watch's error.
    func watch(_ id: TransactionRecord.ID, for key: TransactionRecord.Key) async throws -> TransactionOutcome {
        let entry = entry(for: key)
        if let watch = entry.watches[id] { return try await result(of: watch, for: id, in: entry) }
        await load()
        guard let record = record(id, for: key) else { throw TransactionStoreError.missingRecord }
        guard record.outcome.isPending else { return record.outcome }
        return try await result(of: startWatch(of: record, in: entry), for: id, in: entry)
    }

    /// Starts watching every pending record that has no watch.
    ///
    /// - Parameter replacingFailedWatches: Whether to restart watches that ended with an error that no caller read.
    func resume(replacingFailedWatches: Bool = false) async {
        await load()
        for entry in entries.values {
            for record in entry.records where record.outcome.isPending {
                if let watch = entry.watches[record.id], !(replacingFailedWatches && watch.isFinished) { continue }
                startWatch(of: record, in: entry)
            }
        }
    }

    func erase() async throws {
        await load()
        for entry in entries.values {
            stop(entry)
            entry.records = []
        }
        try await storage.delete()
    }

    /// Stops an account's watches and forgets its records on every network.
    ///
    /// - Parameter account: The identifier of the account.
    /// - Throws: A storage error if the other accounts' pending records can't be saved.
    func erase(account: UUID) async throws {
        await load()
        for key in Network.allCases.map({ TransactionRecord.Key(account: account, network: $0) }) {
            guard let entry = entries.removeValue(forKey: key) else { continue }
            stop(entry)
        }
        try await storage.save(pending)
    }

    /// The records that haven't settled, across every account and network.
    private var pending: [TransactionRecord] {
        entries.values.flatMap(\.records).filter(\.outcome.isPending)
    }

    /// Returns a key's entry, creating it on first use.
    ///
    /// - Parameter key: The account and network.
    /// - Returns: The key's entry.
    private func entry(for key: TransactionRecord.Key) -> Entry {
        if let entry = entries[key] { return entry }
        let entry = Entry()
        entries[key] = entry
        return entry
    }

    /// Stops a key's watches and forgets the settlings that didn't run.
    ///
    /// - Parameter entry: The key's entry.
    private func stop(_ entry: Entry) {
        for watch in entry.watches.values { watch.cancel() }
        entry.watches = [:]
        entry.settlings = [:]
    }

    /// Keeps a pending record as the newest, starts watching it, and saves the pending records.
    ///
    /// - Parameters:
    ///   - record: The pending record.
    ///   - settling: What runs the transaction's remaining work once it settles, or `nil` for nothing.
    /// - Returns: The record.
    private func track(_ record: TransactionRecord, settling: (any TransactionSettling)?) async -> TransactionRecord {
        let entry = entry(for: record.key)
        entry.records.insert(record, at: 0)
        entry.settlings[record.id] = settling
        startWatch(of: record, in: entry)
        await save()
        return record
    }

    /// Saves the pending records after the saved ones were read, ignoring a storage that can't keep them.
    private func save() async {
        await load()
        try? await storage.save(pending)
    }

    /// Starts watching a pending record.
    ///
    /// - Parameters:
    ///   - record: The pending record.
    ///   - entry: The record's key's entry.
    /// - Returns: The running watch.
    @discardableResult
    private func startWatch(of record: TransactionRecord, in entry: Entry) -> TransactionWatch {
        let watch = TransactionWatch { [self] in try await settle(record, in: entry) }
        entry.watches[record.id] = watch
        return watch
    }

    /// Waits for a watch's result, then forgets the watch once it ended.
    ///
    /// - Parameters:
    ///   - watch: The record's watch.
    ///   - id: The record's signature.
    ///   - entry: The record's key's entry.
    /// - Returns: The transaction's settled outcome.
    /// - Throws: `CancellationError` if the caller is cancelled, or the watch's error.
    private func result(of watch: TransactionWatch, for id: TransactionRecord.ID, in entry: Entry) async throws
        -> TransactionOutcome {
        defer { if watch.isFinished, entry.watches[id] === watch { entry.watches[id] = nil } }
        return try await watch.value()
    }

    /// Watches a pending record's transaction until it settles, keeps the outcome, and runs its settling once.
    ///
    /// - Parameters:
    ///   - record: The pending record.
    ///   - entry: The record's key's entry.
    /// - Returns: The transaction's settled outcome.
    /// - Throws: The coordinator's creation or watch error, or `CancellationError`.
    private func settle(_ record: TransactionRecord, in entry: Entry) async throws -> TransactionOutcome {
        let outcome = try await coordinator(for: record.outcome.network).confirm(record.outcome)
        try Task.checkCancellation()
        if let index = entry.records.firstIndex(where: { $0.id == record.id }) {
            entry.records[index].settle(outcome.status, at: .now)
        }
        await save()
        try Task.checkCancellation()
        if let settling = entry.settlings.removeValue(forKey: record.id) { await settling.settle(outcome) }
        entry.settledCount += 1
        return outcome
    }

    /// What the store keeps for one account on one network.
    @MainActor
    @Observable
    fileprivate final class Entry {
        /// The pending records and those that settled since launch, newest first.
        var records: [TransactionRecord] = []
        /// How many of the key's transactions settled since launch.
        var settledCount = 0
        /// The watch of each pending record, kept after it ends until a caller reads its result.
        @ObservationIgnored var watches: [TransactionRecord.ID: TransactionWatch] = [:]
        @ObservationIgnored var settlings: [TransactionRecord.ID: any TransactionSettling] = [:]
    }
}
