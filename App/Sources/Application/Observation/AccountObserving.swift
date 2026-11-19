import Observation
import RPC

/// A store that observes what it keeps for an account on a network.
protocol AccountObserving: AnyObject, Observable {
    /// Observes an account on a network for the lifetime of the calling task.
    ///
    /// - Parameters:
    ///   - account: The account to observe.
    ///   - network: The network to observe the account on.
    func observe(_ account: Account, on network: Network) async
}
