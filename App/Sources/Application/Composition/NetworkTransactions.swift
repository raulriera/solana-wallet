import RPC

/// Keeps one transaction coordinator for each network that a window sends on, shared by every window on that network.
///
/// A network's coordinator is created when a window first needs it, so a network that no window sends on has none.
/// Windows choose their networks separately, so coordinators for several networks can exist at once.
@MainActor
final class NetworkTransactions {
    private let make: (Network) throws -> any TransactionCoordinating
    private var coordinators: [Network: any TransactionCoordinating] = [:]

    /// Creates each network's coordinator when a window first needs it.
    /// - Parameter make: Creates a network's coordinator.
    init(make: @escaping (Network) throws -> any TransactionCoordinating) {
        self.make = make
    }

    /// Returns a network's coordinator, creating it on the first request.
    /// - Parameter network: The network that the window sends on.
    /// - Returns: The coordinator that every window on the network shares.
    /// - Throws: The error of creating the coordinator; the next request tries again.
    func coordinator(for network: Network) throws -> any TransactionCoordinating {
        if let coordinator = coordinators[network] { return coordinator }
        let coordinator = try make(network)
        coordinators[network] = coordinator
        return coordinator
    }
}
