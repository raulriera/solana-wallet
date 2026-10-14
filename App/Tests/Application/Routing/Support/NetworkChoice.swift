import Observation
import RPC

/// Holds a hosted window's network in place of its scene storage, so a test can change it as Settings does.
@MainActor
@Observable
final class NetworkChoice {
    /// The network that the hosted window shows.
    var network: Network

    /// Starts the hosted window on a network.
    /// - Parameter network: The network that the window shows first.
    init(_ network: Network) {
        self.network = network
    }
}
