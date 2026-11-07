import Observation
@testable import RPC
@testable import widgets

extension TransactionStore {
    static func inMemory(_ records: StoredValue<[TransactionRecord]> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating) -> TransactionStore {
        TransactionStore(storage: { _ in records }, pending: StoredValue(), coordinators: coordinators)
    }

    static func inMemory(_ records: [TransactionRecord.Key: StoredValue<[TransactionRecord]>],
                         pending: StoredValue<Set<TransactionRecord.Key>> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating = {
                             try TransactionCoordinator.unused(on: $0)
                         }) -> TransactionStore {
        TransactionStore(storage: { records[$0] ?? StoredValue() }, pending: pending, coordinators: coordinators)
    }

    static var unused: TransactionStore {
        inMemory { try TransactionCoordinator.unused(on: $0) }
    }

    func settledStatus(of record: TransactionRecord) async -> TransactionRecord.Status? {
        for await status in Observations({ self.record(record.id, for: record.key)?.status }) {
            if let status, status != .pending { return status }
        }
        return nil
    }
}

extension TransactionCoordinator {
    static func unused(on network: Network) throws -> TransactionCoordinator {
        try TransactionCoordinator(rpc: SolanaRPC(network: network, transport: HTTPResponses([:])),
                                   store: UnavailableRecoveryStore())
    }
}
