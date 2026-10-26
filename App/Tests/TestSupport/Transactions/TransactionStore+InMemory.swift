import Observation
@testable import RPC
@testable import widgets

extension TransactionStore {
    /// Creates the shared transactions over in-memory records and pending index, without reading them or creating a
    /// coordinator.
    /// - Parameters:
    ///   - records: The in-memory storage of every account's records on every network.
    ///   - coordinators: Creates a network's transaction coordinator.
    /// - Returns: A store that reads nothing until it's used.
    static func inMemory(_ records: StoredValue<[TransactionRecord]> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating) -> TransactionStore {
        TransactionStore(storage: { _ in records }, pending: StoredValue(), coordinators: coordinators)
    }

    /// Creates the shared transactions over each key's own in-memory records and an in-memory pending index, without
    /// reading them or creating a coordinator.
    /// - Parameters:
    ///   - records: The in-memory storage of each key's records; other keys start with no records.
    ///   - pending: The in-memory pending index.
    ///   - coordinators: Creates a network's transaction coordinator; by default, one that never leaves the process.
    /// - Returns: A store that reads nothing until it's used.
    static func inMemory(_ records: [TransactionRecord.Key: StoredValue<[TransactionRecord]>],
                         pending: StoredValue<Set<TransactionRecord.Key>> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating = {
                             try TransactionCoordinator.unused(on: $0)
                         }) -> TransactionStore {
        TransactionStore(storage: { records[$0] ?? StoredValue() }, pending: pending, coordinators: coordinators)
    }

    /// Transactions whose coordinators never leave the process and never read recovery, for models that don't send.
    static var unused: TransactionStore {
        inMemory { try TransactionCoordinator.unused(on: $0) }
    }

    /// Waits until the store shows a record as settled, without watching it; the test's time limit ends the wait if it
    /// never settles.
    /// - Parameter record: The pending record.
    /// - Returns: The settled status.
    func settledStatus(of record: TransactionRecord) async -> TransactionRecord.Status? {
        for await status in Observations({ self.record(record.id, for: record.key)?.status }) {
            // The record shows once its key's records are read.
            if let status, status != .pending { return status }
        }
        return nil
    }
}

extension TransactionCoordinator {
    /// Creates a coordinator whose requests never leave the process and that never reads recovery.
    /// - Parameters:
    ///   - network: The network that the coordinator sends on.
    ///   - routes: The ordinary RPCs that send approved transactions, or `nil` to use the read client alone.
    /// - Returns: The coordinator.
    /// - Throws: ``SubmitterError/noProviders`` without a route on the network.
    static func unused(on network: Network, routes: [any RPC]? = nil) throws -> TransactionCoordinator {
        try TransactionCoordinator(rpc: Solana(network: network, transport: HTTPResponses([:])),
                                   store: UnavailableRecoveryStore(), rpcs: routes)
    }
}
