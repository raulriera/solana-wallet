import Observation
@testable import RPC
@testable import widgets

extension TransactionStore {
    static func inMemory(_ pending: StoredValue<[TransactionRecord]> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating = {
                             try TransactionCoordinator.unused(on: $0)
                         }) -> TransactionStore {
        TransactionStore(storage: pending, coordinators: coordinators)
    }

    static var unused: TransactionStore { inMemory() }

    func outcome(of record: TransactionRecord) async -> TransactionOutcome? {
        for await outcome in Observations({ self.record(record.id, for: record.key)?.outcome }) {
            if let outcome { return outcome }
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
