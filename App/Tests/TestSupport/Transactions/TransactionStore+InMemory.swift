@testable import RPC
@testable import widgets

extension TransactionStore {
    /// Creates the shared transactions over in-memory records, without reading them or creating a coordinator.
    /// - Parameters:
    ///   - records: The in-memory storage of every account's records on every network.
    ///   - coordinators: Creates a network's transaction coordinator.
    /// - Returns: A store that reads nothing until it's used.
    static func inMemory(_ records: StoredValue<[TransactionRecord]> = StoredValue(),
                         coordinators: @escaping (Network) throws -> any TransactionCoordinating) -> TransactionStore {
        TransactionStore(storage: { _ in records }, coordinators: coordinators)
    }

    /// Transactions whose coordinators never leave the process and never read recovery, for models that don't send.
    static var unused: TransactionStore {
        inMemory { try TransactionCoordinator.unused(on: $0) }
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
