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

    func watch(_ record: TransactionRecord,
               untilClosed sockets: SocketSequence) async throws -> TransactionOutcome.Status {
        let outcome = try await watch(record.id, for: record.key)
        await sockets.waitUntilClosed()
        return outcome.status
    }
}

extension TransactionCoordinator {
    static func unused(on network: Network) throws -> TransactionCoordinator {
        try TransactionCoordinator(rpc: SolanaRPC(network: network, transport: HTTPResponses([:])),
                                   store: UnavailableRecoveryStore())
    }
}
